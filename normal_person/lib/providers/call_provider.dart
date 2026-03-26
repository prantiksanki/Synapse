import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/webrtc_call_state.dart';
import '../services/webrtc_service.dart';

class CallProvider extends ChangeNotifier {
  final WebRtcService _service = WebRtcService();

  CallState _state = const CallState();
  String? _pendingCallId;
  String? _username;
  String? _errorMessage;

  final RTCVideoRenderer localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallState get state => _state;
  List<Map<String, dynamic>> get onlineUsers => _service.onlineUsers;
  String? get username => _username;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _service.isConnected;

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _service.onUserListChanged = notifyListeners;

    _service.onIncomingCall = (callId, callerUsername, callType) {
      _pendingCallId = callId;
      _state = _state.copyWith(
        status: CallStatus.ringing,
        remoteUsername: callerUsername,
        callId: callId,
        callType: callType,
      );
      notifyListeners();
    };

    _service.onCallAccepted = (callId) {
      _state = _state.copyWith(status: CallStatus.active);
      notifyListeners();
    };

    _service.onCallRejected = (reason) {
      _errorMessage = reason;
      _state = const CallState();
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () {
        _errorMessage = null;
        notifyListeners();
      });
    };

    _service.onCallEnded = () {
      _state = _state.copyWith(status: CallStatus.ended);
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        _state = const CallState();
        notifyListeners();
      });
    };

    _service.onLocalStream = (stream) {
      localRenderer.srcObject = stream;
      notifyListeners();
    };

    _service.onRemoteStream = (stream) {
      remoteRenderer.srcObject = stream;
      notifyListeners();
    };
  }

  void login(String username) {
    _username = username;
    _service.connect(username);
    notifyListeners();
  }

  Future<void> callUser(String target, {bool video = true}) async {
    _state = _state.copyWith(
      status: CallStatus.calling,
      remoteUsername: target,
      callType: video ? 'video' : 'audio',
    );
    notifyListeners();
    await _service.callUser(target, video: video);
  }

  void acceptCall() {
    if (_pendingCallId == null) return;
    _service.acceptCall(_pendingCallId!);
    _state = _state.copyWith(status: CallStatus.active);
    notifyListeners();
  }

  void rejectCall() {
    if (_pendingCallId == null) return;
    _service.rejectCall(_pendingCallId!);
    _state = const CallState();
    _pendingCallId = null;
    notifyListeners();
  }

  void endCall() {
    _service.endCall();
    _state = const CallState();
    notifyListeners();
  }

  void toggleMic() => _service.toggleMic();
  void toggleCamera() => _service.toggleCamera();

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    _service.dispose();
    super.dispose();
  }
}
