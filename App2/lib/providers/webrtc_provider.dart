import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/detection_provider.dart';
import '../services/webrtc_service.dart';
import '../services/tts_service.dart';

enum WebRtcCallStatus { idle, ringing, active, ended }

/// Orchestrates WebRTC calls for both deaf and caller roles.
/// Hooks into DetectionProvider via the same callback API used by
/// CallBridgeProvider — zero changes to existing core logic.
class WebRtcProvider extends ChangeNotifier {
  final DeafWebRtcService _service = DeafWebRtcService();
  final TtsService _tts = TtsService();

  WebRtcCallStatus _status = WebRtcCallStatus.idle;
  String? _callerUsername;
  String? _pendingCallId;
  String? _callerTranscript;

  DetectionProvider? _detection;

  final RTCVideoRenderer localRenderer  = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  WebRtcCallStatus get status => _status;
  String? get callerUsername => _callerUsername;
  String? get callerTranscript => _callerTranscript;
  bool get isCallActive => _status == WebRtcCallStatus.active;

  /// Exposes online users list from the underlying service.
  List<Map<String, dynamic>> get onlineUsers => _service.onlineUsers;

  /// Whether the socket is currently connected to the signaling server.
  bool get isConnected => _service.isConnected;

  WebRtcProvider() {
    _initRenderers();
    _wireServiceCallbacks();
  }

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  void _wireServiceCallbacks() {
    _service.onUserListChanged = () => notifyListeners();

    _service.onIncomingCall = (callId, callerUsername, callType) {
      _pendingCallId = callId;
      _callerUsername = callerUsername;
      _status = WebRtcCallStatus.ringing;
      notifyListeners();
    };

    _service.onCallActive = () {
      _status = WebRtcCallStatus.active;
      // Tell DetectionProvider to enter call mode — it stops its own STT
      // and starts listening for onSentenceForCall callbacks.
      _detection?.enterCallMode();
      _detection?.onSentenceForCall = _onSentenceReady;
      notifyListeners();
    };

    _service.onCallEnded = () {
      _status = WebRtcCallStatus.ended;
      _detection?.exitCallMode();
      _detection?.onSentenceForCall = null;
      _callerTranscript = null;
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        _status = WebRtcCallStatus.idle;
        _callerUsername = null;
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

  /// Called by ProxyProvider when DetectionProvider is available.
  void setDetectionProvider(DetectionProvider detection) {
    if (_detection == detection) return;
    _detection = detection;
  }

  /// Connect to signaling backend using the saved username + role.
  /// Role is read from SharedPreferences (set during onboarding).
  Future<void> connectFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('webrtc_username') ?? '';
    final role = prefs.getString('user_role') ?? 'deaf';
    if (username.isNotEmpty) {
      _service.connect(username, role);
    }
  }

  /// Connect with an explicit username + role (called from OnboardingScreen).
  void connectWithRole(String username, String role) {
    _service.connect(username, role);
  }

  /// Legacy connect — reads role from SharedPreferences.
  void connect(String username) {
    SharedPreferences.getInstance().then((prefs) {
      final role = prefs.getString('user_role') ?? 'deaf';
      _service.connect(username, role);
    });
  }

  /// Initiate a call to a target user (used by CallerHomeScreen).
  void initiateCall(String targetUsername, {String callType = 'audio'}) {
    _service.callUser(targetUsername, callType: callType);
  }

  Future<void> acceptCall() async {
    if (_pendingCallId == null) return;
    await _service.acceptCall(_pendingCallId!);
    _pendingCallId = null;
  }

  void rejectCall() {
    if (_pendingCallId == null) return;
    _service.rejectCall(_pendingCallId!);
    _pendingCallId = null;
    _status = WebRtcCallStatus.idle;
    _callerUsername = null;
    notifyListeners();
  }

  void endCall() {
    _service.endCall();
    _detection?.exitCallMode();
    _detection?.onSentenceForCall = null;
    _status = WebRtcCallStatus.idle;
    _callerUsername = null;
    _callerTranscript = null;
    notifyListeners();
  }

  /// Fired by DetectionProvider when a sign sentence is complete.
  /// Plays TTS through the speaker → mic → WebRTC mic track → caller hears it.
  void _onSentenceReady(String sentence) {
    if (sentence.trim().isEmpty) return;
    if (_status != WebRtcCallStatus.active) return;
    _tts.speak(sentence);
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    _service.dispose();
    super.dispose();
  }
}
