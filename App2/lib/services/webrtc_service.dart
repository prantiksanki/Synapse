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
  bool _isConnected = false;

  // ── Callbacks ───────────────────────────────────────────────────────────────
  VoidCallback? onUserListChanged;
  void Function(String callId, String callerUsername, String callType)? onIncomingCall;
  VoidCallback? onCallActive;
  VoidCallback? onCallEnded;
  void Function(MediaStream stream)? onLocalStream;
  void Function(MediaStream stream)? onRemoteStream;

  List<Map<String, dynamic>> onlineUsers = [];
  bool get isConnected => _isConnected;
  String? get currentCallId => _currentCallId;

  // ── Connect & register ─────────────────────────────────────────────────────
  void connect(String username, String role) {
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
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[WebRTC] Disconnected');
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
      onIncomingCall?.call(
        d['callId'] as String,
        d['callerUsername'] as String,
        (d['callType'] as String?) ?? 'audio',
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
      await _pc!.setLocalDescription(offer);
      _socket!.emit('offer', {'callId': _currentCallId, 'sdp': offer.toMap()});
      onCallActive?.call();
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
  }

  // ── Initiate a call (caller role) ─────────────────────────────────────────
  void callUser(String targetUsername, {String callType = 'audio'}) {
    _socket?.emit('call_user', {
      'targetUsername': targetUsername,
      'callType': callType,
    });
  }

  // ── Accept incoming call ───────────────────────────────────────────────────
  Future<void> acceptCall(String callId) async {
    _socket!.emit('accept_call', {'callId': callId});
    await _startLocalStream();
    onCallActive?.call();
  }

  // ── Reject incoming call ───────────────────────────────────────────────────
  void rejectCall(String callId) {
    _socket!.emit('reject_call', {'callId': callId});
    _currentCallId = null;
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
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 640, 'height': 480},
    });
    onLocalStream?.call(_localStream!);
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
    await _pc!.setLocalDescription(answer);
    _socket!.emit('answer', {'callId': callId, 'sdp': answer.toMap()});

    await Helper.setSpeakerphoneOn(true);
  }

  // ── Init peer connection ───────────────────────────────────────────────────
  Future<void> _initPeerConnection() async {
    _pc = await createPeerConnection(
      Map<String, dynamic>.from(AppConfig.webrtcIceServers),
    );

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
    Helper.setSpeakerphoneOn(false);
  }

  void dispose() {
    _cleanupPeer();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
