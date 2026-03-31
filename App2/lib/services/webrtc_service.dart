import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

/// WebRTC service for SYNAPSE users (supports both deaf and caller roles).
/// Connects to the signaling backend, handles incoming and outgoing calls,
/// and establishes a peer connection.
class DeafWebRtcService {
  io.Socket? _socket;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentCallId;
  String _currentCallType = 'audio';
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;

  // ── Callbacks ───────────────────────────────────────────────────────────────
  VoidCallback? onUserListChanged;
  VoidCallback? onConnectionChanged;
  void Function(String callId, String callerUsername, String callType)? onIncomingCall;
  void Function(String callType)? onCallActive;
  VoidCallback? onCallEnded;
  void Function(MediaStream stream)? onLocalStream;
  void Function(MediaStream stream)? onRemoteStream;
  /// Called when the remote participant relayed a signed sentence for TTS.
  void Function(String text)? onSignSpeechReceived;

  List<Map<String, dynamic>> onlineUsers = [];
  bool get isConnected => _isConnected;
  String? get currentCallId => _currentCallId;
  String get currentCallType => _currentCallType;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoEnabled => _isVideoEnabled;

  // ── Connect & register ─────────────────────────────────────────────────────
  void connect(String username, String role) {
    final existing = _socket;
    if (existing != null) {
      if (existing.connected) {
        existing.emit('register_user', {'username': username, 'role': role});
        return;
      }
      existing.dispose();
      _socket = null;
    }

    _socket = io.io(
      AppConfig.webrtcBackendUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(3000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('[WebRTC] Connected — registering as $username ($role)');
      _socket!.emit('register_user', {'username': username, 'role': role});
      onConnectionChanged?.call();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[WebRTC] Disconnected');
      onConnectionChanged?.call();
    });

    _socket!.onConnectError((err) {
      _isConnected = false;
      debugPrint('[WebRTC] Connect error: $err');
      onConnectionChanged?.call();
    });

    _socket!.onError((err) {
      debugPrint('[WebRTC] Socket error: $err');
    });

    _socket!.on('user_list', (data) {
      onlineUsers = List<Map<String, dynamic>>.from(
        (data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      onUserListChanged?.call();
    });

    // ── Incoming call ────────────────────────────────────────────────────────
    _socket!.on('incoming_call', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId'] as String;
      _currentCallType = (d['callType'] as String?) ?? 'audio';
      onIncomingCall?.call(
        d['callId'] as String,
        d['callerUsername'] as String,
        _currentCallType,
      );
    });

    // ── Caller: backend confirmed call initiated ─────────────────────────────
    _socket!.on('call_initiated', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId'] as String;
      debugPrint('[WebRTC] Call initiated: $_currentCallId');
    });

    // ── Caller: callee accepted ──────────────────────────────────────────────
    _socket!.on('call_accepted', (data) async {
      debugPrint('[WebRTC] Call accepted — sending offer');
      await _startLocalStream();
      await _initPeerConnection();
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _pc!.addTrack(track, _localStream!);
        }
      }
      final offer = await _pc!.createOffer();
      final cappedOffer = RTCSessionDescription(
        _capSdpBandwidth(offer.sdp!), offer.type,
      );
      await _pc!.setLocalDescription(cappedOffer);
      _socket!.emit('offer', {'callId': _currentCallId, 'sdp': cappedOffer.toMap()});
      onCallActive?.call(_currentCallType);
    });

    // ── Callee: receive offer from caller ────────────────────────────────────
    _socket!.on('offer', (data) async {
      final d = Map<String, dynamic>.from(data as Map);
      await _handleOffer(
        d['callId'] as String,
        Map<String, dynamic>.from(d['sdp'] as Map),
      );
    });

    // ── Caller: receive answer from callee ───────────────────────────────────
    _socket!.on('answer', (data) async {
      final d = Map<String, dynamic>.from(data as Map);
      final sdp = Map<String, dynamic>.from(d['sdp'] as Map);
      await _pc?.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
      );
    });

    _socket!.on('ice_candidate', (data) async {
      final d = Map<String, dynamic>.from(data as Map);
      final c = d['candidate'];
      if (c != null) {
        final cm = Map<String, dynamic>.from(c as Map);
        await _pc?.addCandidate(RTCIceCandidate(
          cm['candidate'] as String,
          cm['sdpMid'] as String?,
          cm['sdpMLineIndex'] as int?,
        ));
      }
    });

    _socket!.on('call_rejected', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      debugPrint('[WebRTC] Call rejected: ${d['reason']}');
      _cleanupPeer();
      onCallEnded?.call();
    });

    _socket!.on('call_ended', (_) {
      _cleanupPeer();
      onCallEnded?.call();
    });

    // ── Sign speech relay — deaf user's signed text arrives here on caller side ─
    _socket!.on('sign_speech', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      final text = d['text'] as String?;
      if (text != null && text.isNotEmpty) {
        onSignSpeechReceived?.call(text);
      }
    });
  }

  // ── Initiate a call (caller role) ─────────────────────────────────────────
  void callUser(String targetUsername, {String callType = 'audio'}) {
    _currentCallType = callType;
    _socket?.emit('call_user', {
      'targetUsername': targetUsername,
      'callType': callType,
    });
  }

  // ── Accept incoming call ───────────────────────────────────────────────────
  Future<void> acceptCall(String callId) async {
    await _startLocalStream();
    _socket!.emit('accept_call', {'callId': callId});
    onCallActive?.call(_currentCallType);
  }

  // ── Reject incoming call ───────────────────────────────────────────────────
  void rejectCall(String callId) {
    _socket!.emit('reject_call', {'callId': callId});
    _currentCallId = null;
  }

  // ── Send signed sentence to remote participant for TTS playback ───────────
  void sendSignSpeech(String text) {
    if (_currentCallId == null || _socket == null) return;
    _socket!.emit('sign_speech', {'callId': _currentCallId, 'text': text});
    debugPrint('[WebRTC] sign_speech sent: $text');
  }

  // ── End active call ────────────────────────────────────────────────────────
  void endCall() {
    if (_currentCallId != null) {
      _socket!.emit('end_call', {'callId': _currentCallId});
    }
    _cleanupPeer();
  }

  // ── Start local media ─────────────────────────────────────────────────────
  Future<void> _startLocalStream() async {
    final wantsVideo = _currentCallType == 'video';
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': wantsVideo
          ? {
              'facingMode': 'user',
              // 480p max — enough for a call, much lighter on CPU/network than 720p.
              'width': {'ideal': 480, 'max': 640},
              'height': {'ideal': 360, 'max': 480},
              // Cap capture frame rate to 24fps — smooth but not wasteful.
              'frameRate': {'ideal': 24, 'max': 24},
            }
          : false,
    });
    _isMuted = false;
    _isSpeakerOn = true;
    _isVideoEnabled = wantsVideo;
    _setAudioTrackEnabled(!_isMuted);
    _setVideoTrackEnabled(_isVideoEnabled);
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    onLocalStream?.call(_localStream!);
  }

  // ── Inject bandwidth limit into SDP ───────────────────────────────────────
  // Caps video at 500 kbps and audio at 50 kbps via SDP b=AS lines.
  // This prevents the encoder from flooding a slow link and causing jitter.
  String _capSdpBandwidth(String sdp) {
    final lines = sdp.split('\r\n');
    final out = <String>[];
    for (final line in lines) {
      out.add(line);
      if (line.startsWith('m=video')) {
        out.add('b=AS:500'); // 500 kbps video max
      } else if (line.startsWith('m=audio')) {
        out.add('b=AS:50'); // 50 kbps audio max
      }
    }
    return out.join('\r\n');
  }

  // ── Handle WebRTC offer (callee side) ─────────────────────────────────────
  Future<void> _handleOffer(String callId, Map<String, dynamic> sdp) async {
    _currentCallId = callId;
    await _initPeerConnection();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    }

    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
    );

    final answer = await _pc!.createAnswer();
    final cappedAnswer = RTCSessionDescription(
      _capSdpBandwidth(answer.sdp!), answer.type,
    );
    await _pc!.setLocalDescription(cappedAnswer);
    _socket!.emit('answer', {'callId': callId, 'sdp': cappedAnswer.toMap()});

    await Helper.setSpeakerphoneOn(true);
  }

  // ── Init peer connection ───────────────────────────────────────────────────
  Future<void> _initPeerConnection() async {
    final config = {
      ...Map<String, dynamic>.from(AppConfig.webrtcIceServers),
      // Unified-plan is the modern SDP format; required for multi-track calls.
      'sdpSemantics': 'unified-plan',
      // Bundle all media over one transport — fewer sockets, lower latency.
      'bundlePolicy': 'max-bundle',
      // Only use UDP ICE candidates (TCP adds ~50ms latency on mobile).
      'iceTransportPolicy': 'all',
    };
    _pc = await createPeerConnection(config);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _socket!.emit('ice_candidate', {
          'callId': _currentCallId,
          'candidate': candidate.toMap(),
        });
      }
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream!);
        return;
      }
      // Some devices emit tracks with an empty streams array.
      // Accumulate all tracks into one synthetic stream.
      if (event.track.kind == 'video' || event.track.kind == 'audio') {
        if (_remoteStream != null) {
          _remoteStream!.addTrack(event.track);
          onRemoteStream?.call(_remoteStream!);
        } else {
          createLocalMediaStream('remote_fallback').then((fallback) {
            fallback.addTrack(event.track);
            _remoteStream = fallback;
            onRemoteStream?.call(_remoteStream!);
          });
        }
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanupPeer();
        onCallEnded?.call();
      }
    };
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────
  void _cleanupPeer() {
    _pc?.close();
    _pc = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _remoteStream?.dispose();
    _remoteStream = null;
    _currentCallId = null;
    _currentCallType = 'audio';
    _isMuted = false;
    _isSpeakerOn = true;
    _isVideoEnabled = true;
    Helper.setSpeakerphoneOn(false);
  }

  Future<bool> toggleMute() async {
    _isMuted = !_isMuted;
    _setAudioTrackEnabled(!_isMuted);
    return _isMuted;
  }

  Future<bool> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    return _isSpeakerOn;
  }

  Future<bool> toggleVideo() async {
    _isVideoEnabled = !_isVideoEnabled;
    _setVideoTrackEnabled(_isVideoEnabled);
    return _isVideoEnabled;
  }

  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTracks = _localStream!
        .getVideoTracks()
        .where((track) => track.kind == 'video')
        .toList();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  void _setAudioTrackEnabled(bool enabled) {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  void _setVideoTrackEnabled(bool enabled) {
    if (_localStream == null) return;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  void dispose() {
    _cleanupPeer();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
