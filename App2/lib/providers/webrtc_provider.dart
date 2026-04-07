import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/speech_service.dart';
import '../services/webrtc_service.dart';

enum WebRtcCallStatus { idle, ringing, active, ended }

/// Holds the data for a sign received from (or sent to) the remote participant.
class ReceivedSignItem {
  final String gifPath;
  final String label;
  const ReceivedSignItem(this.gifPath, this.label);
}

/// Orchestrates WebRTC calls for both deaf and caller roles.
///
/// Performance design:
/// - [callDurationNotifier] is a ValueNotifier updated every second.
///   The call screen uses ValueListenableBuilder for the timer so only that
///   widget rebuilds — NOT the entire provider tree (no notifyListeners).
/// - [transcriptNotifier] is a ValueNotifier updated on every STT partial.
///   Only the transcript text widget rebuilds; the video renderer is untouched.
/// - [receivedSignNotifier] is a ValueNotifier updated when a sign panel item
///   arrives from the remote participant; the overlay widget subscribes to it.
/// - notifyListeners() is called only for genuine call-state transitions
///   (ringing → active → ended, mute/speaker toggles, user list changes).
class WebRtcProvider extends ChangeNotifier {
  final DeafWebRtcService _service = DeafWebRtcService();
  final SpeechService _remoteStt = SpeechService();

  WebRtcCallStatus _status = WebRtcCallStatus.idle;
  String? _callerUsername;
  String? _pendingCallId;
  String _pendingCallType = 'audio';
  String _currentCallType = 'audio';
  String _userRole = 'deaf';
  String _myUsername = '';

  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  Timer? _callTimer;
  bool _startingRemoteStt = false;

  // ── Zero-rebuild notifiers ─────────────────────────────────────────────────
  /// Updated every second without calling notifyListeners().
  final ValueNotifier<Duration> callDurationNotifier =
      ValueNotifier(Duration.zero);

  /// Updated on every STT partial result without calling notifyListeners().
  final ValueNotifier<String> transcriptNotifier = ValueNotifier('');

  /// Updated when a sign panel item arrives from the remote participant.
  final ValueNotifier<ReceivedSignItem?> receivedSignNotifier =
      ValueNotifier(null);

  // ── Renderers ──────────────────────────────────────────────────────────────
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // ── Getters ────────────────────────────────────────────────────────────────
  WebRtcCallStatus get status => _status;
  String? get callerUsername => _callerUsername;
  bool get isCallActive => _status == WebRtcCallStatus.active;
  String get pendingCallType => _pendingCallType;
  String get currentCallType => _currentCallType;
  bool get isAudioCall => _currentCallType != 'video';
  String get userRole => _userRole;
  String get myUsername => _myUsername;

  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoEnabled => _isVideoEnabled;

  String get remoteTranscript => transcriptNotifier.value;

  bool get isRemoteListening => _remoteStt.isListening;

  List<Map<String, dynamic>> get onlineUsers => _service.onlineUsers;
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
    _service.onConnectionChanged = () => notifyListeners();
    _service.onUserListChanged = () => notifyListeners();

    _service.onIncomingCall = (callId, callerUsername, callType) {
      _pendingCallId = callId;
      _pendingCallType = callType;
      _currentCallType = callType;
      _callerUsername = callerUsername;
      _status = WebRtcCallStatus.ringing;
      notifyListeners();
    };

    _service.onCallActive = (callType) {
      _status = WebRtcCallStatus.active;
      _currentCallType = callType;
      _isMuted = _service.isMuted;
      _isSpeakerOn = _service.isSpeakerOn;
      _isVideoEnabled = _service.isVideoEnabled;
      callDurationNotifier.value = Duration.zero;
      _startCallTimer();
      unawaited(_startRemoteStt());
      notifyListeners(); // one notify: state → active
    };

    _service.onCallEnded = () {
      _status = WebRtcCallStatus.ended;
      unawaited(_stopRemoteStt());
      _stopCallTimer();
      notifyListeners(); // one notify: state → ended
      Future.delayed(const Duration(seconds: 2), _resetAfterCall);
    };

    _service.onLocalStream = (stream) {
      localRenderer.srcObject = stream;
      notifyListeners();
    };

    _service.onRemoteStream = (stream) {
      remoteRenderer.srcObject = stream;
      notifyListeners();
    };

    _service.onSignPanelReceived = (gifPath, label) {
      receivedSignNotifier.value = ReceivedSignItem(gifPath, label);
    };
  }

  // ── Call timer — ValueNotifier, no notifyListeners() ──────────────────────
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != WebRtcCallStatus.active) return;
      callDurationNotifier.value += const Duration(seconds: 1);
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String formatDuration() {
    final d = callDurationNotifier.value;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // ── Remote STT — transcript goes to ValueNotifier only ────────────────────
  Future<void> _startRemoteStt() async {
    if (_status != WebRtcCallStatus.active) return;
    if (_remoteStt.isListening || _startingRemoteStt) return;

    await Helper.setSpeakerphoneOn(true);
    _startingRemoteStt = true;
    try {
      final ready = await _remoteStt.initialize();
      if (!ready) return;

      _remoteStt.onResult = (text, isFinal) {
        // Update ValueNotifier only — NO notifyListeners(), NO video rebuild.
        transcriptNotifier.value = text;
      };

      _remoteStt.onStopped = () {
        if (_status == WebRtcCallStatus.active) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_status == WebRtcCallStatus.active) {
              unawaited(_startRemoteStt());
            }
          });
        }
      };

      await _remoteStt.startListening();
    } catch (_) {
      // Keep call active even when remote STT fails.
    } finally {
      _startingRemoteStt = false;
    }
  }

  Future<void> _stopRemoteStt() async {
    _startingRemoteStt = false;
    await _remoteStt.stopListening();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> connectFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('webrtc_username') ?? '';
    final role = prefs.getString('user_role') ?? 'deaf';
    _userRole = role;
    _myUsername = username;
    if (username.isNotEmpty) _service.connect(username, role);
  }

  void connectWithRole(String username, String role) {
    _userRole = role;
    _myUsername = username;
    _service.connect(username, role);
  }

  void connect(String username) {
    SharedPreferences.getInstance().then((prefs) {
      final role = prefs.getString('user_role') ?? 'deaf';
      _userRole = role;
      _myUsername = username;
      _service.connect(username, role);
    });
  }

  void initiateCall(String targetUsername, {String callType = 'audio'}) {
    _callerUsername = targetUsername;
    _currentCallType = callType;
    _status = WebRtcCallStatus.ringing;
    _service.callUser(targetUsername, callType: callType);
    notifyListeners();
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
    unawaited(_stopRemoteStt());
    _stopCallTimer();
    _resetAfterCall();
  }

  /// Sends a sign GIF to the remote participant and mirrors it locally
  /// so the sender gets immediate visual feedback.
  void sendSign(String gifPath, String label) {
    _service.sendSignPanelItem(gifPath, label);
    receivedSignNotifier.value = ReceivedSignItem(gifPath, label);
  }

  Future<void> toggleMute() async {
    _isMuted = await _service.toggleMute();
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = await _service.toggleSpeaker();
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _isVideoEnabled = await _service.toggleVideo();
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _service.switchCamera();
  }

  void _resetAfterCall() {
    _status = WebRtcCallStatus.idle;
    _callerUsername = null;
    _pendingCallId = null;
    _pendingCallType = 'audio';
    _currentCallType = 'audio';
    _isMuted = false;
    _isSpeakerOn = true;
    _isVideoEnabled = true;
    callDurationNotifier.value = Duration.zero;
    transcriptNotifier.value = '';
    receivedSignNotifier.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    callDurationNotifier.dispose();
    transcriptNotifier.dispose();
    receivedSignNotifier.dispose();
    unawaited(_remoteStt.stopListening());
    _remoteStt.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _service.dispose();
    super.dispose();
  }
}
