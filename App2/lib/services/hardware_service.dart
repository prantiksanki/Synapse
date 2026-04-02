import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../config/app_config.dart';
import '../models/connection_state.dart';
import '../models/hw_info.dart';

/// SYNAPSE Hardware Service - WebRTC edition aligned with `files/server.py`.
///
/// Socket.IO is used only for signalling and health events:
///   offer/answer/ice_candidate, hw_info, ping_hw/pong_hw, hw_error.
///
/// WebRTC carries media + data:
///   Pi -> App: camera video + mic audio
///   App -> Pi: phone mic audio + DataChannel('screen') text
class HardwareService {
  static HardwareService? _instance;

  factory HardwareService() {
    _instance ??= HardwareService._internal();
    return _instance!;
  }

  HardwareService._internal();

  socket_io.Socket? _socket;
  Timer? _retryTimer;
  Timer? _pingTimer;
  int _pingTimestamp = 0;
  Duration _retryDelay = const Duration(seconds: 3);
  static const Duration _maxRetryDelay = Duration(seconds: 30);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  RTCPeerConnection? _pc;
  RTCDataChannel? _screenChannel;
  MediaStream? _localStream;

  /// Pi camera renderer target for WebRTC UI screens.
  final RTCVideoRenderer remoteVideoRenderer = RTCVideoRenderer();
  bool _rendererInitialized = false;

  /// Legacy compatibility shims. These are intentionally unused in WebRTC mode.
  void Function(Uint8List jpeg)? onFrame;
  void Function(Uint8List pcm)? onAudio;

  final ValueNotifier<HwStatus> status =
      ValueNotifier(const HwStatus.disconnected());

  bool _disposed = false;
  bool _connecting = false;

  Future<void> connect() async {
    if (_disposed) return;
    await _ensureRendererInit();

    _connectivitySub ??=
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    final results = await Connectivity().checkConnectivity();
    if (_hasWifi(results)) {
      await _tryConnect();
    } else {
      _setStatus(const HwStatus.disconnected());
    }
  }

  /// Send text to Pi HDMI display via WebRTC data channel "screen".
  void updateScreen({String top = '', String mid = '', String bot = ''}) {
    final payload = jsonEncode({'top': top, 'mid': mid, 'bot': bot});
    if (_screenChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _screenChannel!.send(RTCDataChannelMessage(payload));
      return;
    }

    // Fallback for race windows before data channel opens.
    _socketEmit('update_screen', {'top': top, 'mid': mid, 'bot': bot});
  }

  /// Legacy TTS bridge exposed by hardware server.
  void speak(String text) => _socketEmit('speak', {'text': text});

  bool _hasWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    if (_hasWifi(results)) {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), () {
        if (!_disposed && !_connecting && _socket?.connected != true) {
          _retryDelay = const Duration(seconds: 3);
          _tryConnect();
        }
      });
    } else {
      _cancelSocket();
      _closeWebRTC();
      _retryTimer?.cancel();
      _setStatus(const HwStatus.disconnected());
    }
  }

  Future<void> _tryConnect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _setStatus(HwStatus(status: HwConnectionStatus.connecting));

    try {
      _socket?.dispose();
      _socket = socket_io.io(
        AppConfig.hwSocketUrl,
        socket_io.OptionBuilder()
            .setTransports(['polling', 'websocket'])
            .disableAutoConnect()
            .disableReconnection()
            .setTimeout(4000)
            .build(),
      );
      _setupSocketListeners();
      _socket!.connect();
    } catch (e) {
      debugPrint('[HardwareService] socket connect error: $e');
      _connecting = false;
      _setStatus(const HwStatus.disconnected());
      _scheduleRetry();
    }
  }

  void _setupSocketListeners() {
    final socket = _socket!;

    socket.onConnect((_) async {
      debugPrint('[HardwareService] signalling socket connected');
      _connecting = false;
      _retryDelay = const Duration(seconds: 3);
      _setStatus(HwStatus(status: HwConnectionStatus.connected));
      _startPingTimer();
      await _startWebRTC();
    });

    socket.onDisconnect((_) {
      debugPrint('[HardwareService] signalling socket disconnected');
      _connecting = false;
      _pingTimer?.cancel();
      _closeWebRTC();
      _setStatus(const HwStatus.disconnected());
      if (!_disposed) _scheduleRetry();
    });

    socket.onError((e) => debugPrint('[HardwareService] socket error: $e'));

    socket.onConnectError((e) {
      debugPrint('[HardwareService] connect error: $e');
      _connecting = false;
      _setStatus(const HwStatus.disconnected());
      if (!_disposed) _scheduleRetry();
    });

    socket.on('hw_info', (data) {
      try {
        final info = HwInfo.fromJson(Map<String, dynamic>.from(data as Map));
        _setStatus(HwStatus(
          status: HwConnectionStatus.hardwareReady,
          info: info,
          latencyMs: status.value.latencyMs,
        ));
        debugPrint('[HardwareService] hw_info: ${info.device} v${info.version}');
      } catch (e) {
        debugPrint('[HardwareService] hw_info parse error: $e');
      }
    });

    socket.on('answer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final desc = RTCSessionDescription(
          map['sdp'] as String,
          map['type'] as String,
        );
        await _pc?.setRemoteDescription(desc);
        debugPrint('[HardwareService] Remote description (answer) set');
      } catch (e) {
        debugPrint('[HardwareService] setRemoteDescription error: $e');
      }
    });

    socket.on('ice_candidate', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final candidate = RTCIceCandidate(
          map['candidate'] as String,
          map['sdpMid'] as String?,
          map['sdpMLineIndex'] as int?,
        );
        await _pc?.addCandidate(candidate);
      } catch (e) {
        debugPrint('[HardwareService] addCandidate error: $e');
      }
    });

    socket.on('hw_error', (data) {
      debugPrint('[HardwareService] hw_error: $data');
      _setStatus(HwStatus(
        status: status.value.status,
        info: status.value.info,
        latencyMs: status.value.latencyMs,
        error: data?.toString(),
      ));
    });

    socket.on('pong_hw', (_) {
      if (_pingTimestamp > 0) {
        final latency = DateTime.now().millisecondsSinceEpoch - _pingTimestamp;
        _pingTimestamp = 0;
        _setStatus(HwStatus(
          status: status.value.status,
          info: status.value.info,
          latencyMs: latency,
          error: status.value.error,
        ));
      }
    });
  }

  Future<void> _startWebRTC() async {
    if (_disposed) return;
    _closeWebRTC();

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    debugPrint('[HardwareService] Local audio track added');

    _screenChannel = await _pc!.createDataChannel(
      'screen',
      RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 3,
    );
    _screenChannel!.onDataChannelState = (state) {
      debugPrint('[HardwareService] DataChannel state: $state');
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      final track = event.track;
      debugPrint('[HardwareService] Received remote track: ${track.kind}');

      if (track.kind == 'video' && event.streams.isNotEmpty) {
        remoteVideoRenderer.srcObject = event.streams.first;
        debugPrint('[HardwareService] Camera stream attached to renderer');
      }
      // Remote audio is played by WebRTC platform audio engine.
    };

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      _socketEmit('ice_candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[HardwareService] PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _closeWebRTC();
        if (!_disposed && _socket?.connected == true) {
          _scheduleRetry();
        }
      }
    };

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _pc!.setLocalDescription(offer);

    _socketEmit('offer', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
    debugPrint('[HardwareService] WebRTC offer sent to Pi');
  }

  void _closeWebRTC() {
    try {
      _screenChannel?.close();
    } catch (_) {}
    _screenChannel = null;

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;

    remoteVideoRenderer.srcObject = null;
  }

  Future<void> _ensureRendererInit() async {
    if (!_rendererInitialized) {
      await remoteVideoRenderer.initialize();
      _rendererInitialized = true;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    debugPrint('[HardwareService] retry in ${_retryDelay.inSeconds}s');
    _retryTimer = Timer(_retryDelay, () async {
      if (_disposed) return;
      final r = await Connectivity().checkConnectivity();
      if (_hasWifi(r)) _tryConnect();
    });
    final next = Duration(seconds: _retryDelay.inSeconds * 2);
    _retryDelay = next > _maxRetryDelay ? _maxRetryDelay : next;
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(AppConfig.hwPingInterval, (_) {
      if (_socket?.connected == true) {
        _pingTimestamp = DateTime.now().millisecondsSinceEpoch;
        _socketEmit('ping_hw', {});
      }
    });
  }

  void _cancelSocket() {
    _pingTimer?.cancel();
    _socket?.dispose();
    _socket = null;
    _connecting = false;
  }

  void _setStatus(HwStatus s) {
    if (!_disposed) status.value = s;
  }

  void _socketEmit(String event, dynamic data) {
    if (_socket?.connected == true) {
      _socket!.emit(event, data);
    }
  }

  // ---------------------------------------------------------------------------
  // Compatibility shims (legacy API preserved, intentionally no-op for media)
  // ---------------------------------------------------------------------------

  void startMic() {
    // Media is negotiated via WebRTC. Kept for backward compatibility.
    _socketEmit('start_mic', {});
  }

  void stopMic() {
    // Media is negotiated via WebRTC. Kept for backward compatibility.
    _socketEmit('stop_mic', {});
  }

  void startStream() {
    // Pi server handles media via WebRTC tracks; this event is legacy no-op.
    _socketEmit('start_stream', {
      'fps': AppConfig.hwStreamFps,
      'quality': AppConfig.hwStreamQuality,
    });
  }

  void stopStream() {
    // Legacy no-op / remote-side compatibility event.
    _socketEmit('stop_stream', {});
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _connectivitySub?.cancel();
    _closeWebRTC();
    _cancelSocket();
    remoteVideoRenderer.dispose();
    status.dispose();
  }
}
