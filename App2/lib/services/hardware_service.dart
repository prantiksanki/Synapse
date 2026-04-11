import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/connection_state.dart';
import '../models/hw_info.dart';

/// SYNAPSE Hardware Service — receive-only WebRTC client.
///
/// Pi → App : camera video + mic audio
/// App → Pi : NOTHING (one-way stream)
class HardwareService {
  static HardwareService? _instance;

  factory HardwareService() {
    _instance ??= HardwareService._internal();
    return _instance!;
  }

  HardwareService._internal();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  Timer? _retryTimer;
  Timer? _pingTimer;
  Duration _retryDelay = const Duration(seconds: 3);
  static const Duration _maxRetryDelay = Duration(seconds: 30);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  RTCPeerConnection? _pc;

  /// Single MediaStream that holds BOTH the video and audio tracks from Pi.
  /// Critical: must be one stream so the <video> element plays audio too.
  MediaStream? _remoteStream;

  final RTCVideoRenderer remoteVideoRenderer = RTCVideoRenderer();
  bool _rendererInitialized = false;

  /// Legacy callbacks — never called, kept for API compatibility.
  void Function(Uint8List jpeg)? onFrame;
  void Function(Uint8List pcm)? onAudio;

  final ValueNotifier<HwStatus> status =
      ValueNotifier(const HwStatus.disconnected());

  bool _disposed = false;
  bool _connecting = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

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

  void updateScreen({String top = '', String mid = '', String bot = ''}) {}
  void speak(String text) {}

  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------

  bool _hasWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    if (_hasWifi(results)) {
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), () {
        if (!_disposed && !_connecting && !_isConnected) {
          _retryDelay = const Duration(seconds: 3);
          _tryConnect();
        }
      });
    } else {
      _retryTimer?.cancel();
      _pingTimer?.cancel();
      _closeWebRTC();
      _setStatus(const HwStatus.disconnected());
    }
  }

  bool get _isConnected =>
      status.value.status == HwConnectionStatus.connected ||
      status.value.status == HwConnectionStatus.hardwareReady;

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _tryConnect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _setStatus(HwStatus(status: HwConnectionStatus.connecting));

    try {
      await _startWebRTC();
    } catch (e) {
      debugPrint('[HardwareService] connect error: $e');
      _connecting = false;
      _closeWebRTC();
      _setStatus(const HwStatus.disconnected());
      _scheduleRetry();
    }
  }

  Future<void> _startWebRTC() async {
    if (_disposed) return;
    _closeWebRTC();

    // ---- Peer connection ----
    const config = {
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    };
    _pc = await createPeerConnection(config);

    // ---- Single MediaStream to hold remote tracks ----
    _remoteStream = await createLocalMediaStream('remote_pi_stream');
    remoteVideoRenderer.srcObject = _remoteStream;

    // ---- Receive-only transceivers (no phone mic upload) ----
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    // ---- Track handler — add ALL tracks (video + audio) to the same stream ----
    _pc!.onTrack = (RTCTrackEvent event) {
      final track = event.track;
      debugPrint('[HardwareService] remote track: ${track.kind}');

      _remoteStream?.addTrack(track);

      if (track.kind == 'video') {
        // Re-assign srcObject so renderer picks up the new track
        remoteVideoRenderer.srcObject = _remoteStream;
        debugPrint('[HardwareService] Pi camera attached');
        _setStatus(HwStatus(
          status: HwConnectionStatus.hardwareReady,
          info: _syntheticHwInfo(),
          latencyMs: status.value.latencyMs,
        ));
      } else if (track.kind == 'audio') {
        // Force-enable so phone speaker plays it
        track.enabled = true;
        debugPrint('[HardwareService] Pi mic attached');
      }
    };

    // ---- Connection state handling ----
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[HardwareService] PeerConnection: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connecting = false;
        _retryDelay = const Duration(seconds: 3);
        if (status.value.status != HwConnectionStatus.hardwareReady) {
          _setStatus(HwStatus(status: HwConnectionStatus.connected));
        }
        _startPingTimer();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _pingTimer?.cancel();
        _closeWebRTC();
        _setStatus(const HwStatus.disconnected());
        if (!_disposed) _scheduleRetry();
      }
    };

    // ---- Create + send offer ----
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await _waitForIceGathering();

    debugPrint('[HardwareService] POSTing offer to ${AppConfig.hwOfferUrl}');
    final response = await http
        .post(
          Uri.parse(AppConfig.hwOfferUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError('Pi /offer returned ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final answer = RTCSessionDescription(
      body['sdp'] as String,
      body['type'] as String,
    );
    await _pc!.setRemoteDescription(answer);
    debugPrint('[HardwareService] SDP answer applied');
  }

  Future<void> _waitForIceGathering() async {
    if (_pc == null) return;
    final completer = Completer<void>();

    _pc!.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint('[HardwareService] ICE gathering timeout — proceeding');
      },
    );
  }

  void _closeWebRTC() {
    try {
      _remoteStream?.getTracks().forEach((t) => t.stop());
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

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

  // ---------------------------------------------------------------------------
  // Retry / ping
  // ---------------------------------------------------------------------------

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
    _pingTimer = Timer.periodic(AppConfig.hwPingInterval, (_) async {
      if (_disposed || !_isConnected) return;
      final t0 = DateTime.now().millisecondsSinceEpoch;
      try {
        await http
            .get(Uri.parse(AppConfig.hwBaseUrl))
            .timeout(const Duration(seconds: 3));
        final latency = DateTime.now().millisecondsSinceEpoch - t0;
        _setStatus(HwStatus(
          status: status.value.status,
          info: status.value.info,
          latencyMs: latency,
          error: status.value.error,
        ));
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  HwInfo _syntheticHwInfo() => const HwInfo(
        device: 'VAANI-HW',
        version: '2.0',
        ip: '',
        camera: '/dev/video0',
        cameraOk: true,
        micOk: true,
        speakerOk: false,
      );

  void _setStatus(HwStatus s) {
    if (!_disposed) status.value = s;
  }

  // Legacy shims
  void startMic() {}
  void stopMic() {}
  void startStream() {}
  void stopStream() {}

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _connectivitySub?.cancel();
    _closeWebRTC();
    remoteVideoRenderer.dispose();
    status.dispose();
  }
}
