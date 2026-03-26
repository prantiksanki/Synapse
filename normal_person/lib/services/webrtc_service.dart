import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';

class WebRtcService {
  io.Socket? _socket;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _currentCallId;
  bool _isConnected = false;

  // ── Callbacks ──────────────────────────────────────────────────────────────
  VoidCallback? onUserListChanged;
  void Function(String callId, String callerUsername, String callType)? onIncomingCall;
  void Function(String callId)? onCallAccepted;
  void Function(String reason)? onCallRejected;
  VoidCallback? onCallEnded;
  void Function(MediaStream stream)? onLocalStream;
  void Function(MediaStream stream)? onRemoteStream;
  void Function(String error)? onError;

  List<Map<String, dynamic>> onlineUsers = [];

  bool get isConnected => _isConnected;
  String? get currentCallId => _currentCallId;

  // ── Connect to signaling server ────────────────────────────────────────────
  void connect(String username) {
    _socket = io.io(
      AppConfig.backendUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('[WS] Connected to signaling server');
      _socket!.emit('register_user', {
        'username': username,
        'role': AppConfig.userRole,
      });
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[WS] Disconnected from signaling server');
    });

    _socket!.on('user_list', (data) {
      onlineUsers = List<Map<String, dynamic>>.from(
        (data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      onUserListChanged?.call();
    });

    _socket!.on('incoming_call', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId'] as String;
      onIncomingCall?.call(
        d['callId'] as String,
        d['callerUsername'] as String,
        (d['callType'] as String?) ?? 'audio',
      );
    });

    _socket!.on('call_initiated', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId'] as String;
    });

    _socket!.on('call_accepted', (data) async {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId'] as String;
      onCallAccepted?.call(d['callId'] as String);
      // Caller creates the offer after callee accepts
      await _createOffer();
    });

    _socket!.on('call_rejected', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      onCallRejected?.call((d['reason'] as String?) ?? 'Call rejected');
      _currentCallId = null;
    });

    _socket!.on('call_ended', (_) {
      _cleanupPeer();
      onCallEnded?.call();
    });

    _socket!.on('offer', (data) async {
      final d = Map<String, dynamic>.from(data as Map);
      await _handleOffer(
        d['callId'] as String,
        Map<String, dynamic>.from(d['sdp'] as Map),
      );
    });

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
  }

  // ── Start local media stream ───────────────────────────────────────────────
  Future<void> startLocalStream({bool video = true}) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    onLocalStream?.call(_localStream!);
  }

  // ── Initiate a call ────────────────────────────────────────────────────────
  Future<void> callUser(String targetUsername, {bool video = true}) async {
    await startLocalStream(video: video);
    _socket!.emit('call_user', {
      'targetUsername': targetUsername,
      'callType': video ? 'video' : 'audio',
    });
  }

  void acceptCall(String callId) =>
      _socket!.emit('accept_call', {'callId': callId});

  void rejectCall(String callId) =>
      _socket!.emit('reject_call', {'callId': callId});

  void endCall() {
    if (_currentCallId != null) {
      _socket!.emit('end_call', {'callId': _currentCallId});
    }
    _cleanupPeer();
  }

  // ── Create WebRTC offer (caller side) ─────────────────────────────────────
  Future<void> _createOffer() async {
    await _initPeerConnection();
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    final offer = await _pc!.createOffer(AppConfig.sdpConstraints);
    await _pc!.setLocalDescription(offer);
    _socket!.emit('offer', {'callId': _currentCallId, 'sdp': offer.toMap()});
  }

  // ── Handle WebRTC offer (callee side — not used in caller app but kept for symmetry) ──
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
    await _pc!.setLocalDescription(answer);
    _socket!.emit('answer', {'callId': callId, 'sdp': answer.toMap()});
  }

  // ── Initialize peer connection ─────────────────────────────────────────────
  Future<void> _initPeerConnection() async {
    _pc = await createPeerConnection(Map<String, dynamic>.from(AppConfig.iceServers));

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
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection state: $state');
    };
  }

  // ── Toggle mic / camera ────────────────────────────────────────────────────
  void toggleMic() {
    for (final t in _localStream?.getAudioTracks() ?? []) {
      t.enabled = !t.enabled;
    }
  }

  void toggleCamera() {
    for (final t in _localStream?.getVideoTracks() ?? []) {
      t.enabled = !t.enabled;
    }
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
  }

  void dispose() {
    _cleanupPeer();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
