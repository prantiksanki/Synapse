import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/detection_provider.dart';
import '../services/sign_image_service.dart';
import '../services/speech_service.dart';
import '../services/webrtc_service.dart';

enum WebRtcCallStatus { idle, ringing, active, ended }

/// Orchestrates WebRTC calls for both deaf and caller roles.
///
/// Performance design:
/// - [callDurationNotifier] is a ValueNotifier updated every second.
///   The call screen uses ValueListenableBuilder for the timer so only that
///   widget rebuilds — NOT the entire provider tree (no notifyListeners).
/// - [transcriptNotifier] is a ValueNotifier updated on every STT partial.
///   Only the transcript text widget rebuilds; the video renderer is untouched.
/// - Sign translation runs via [processCallerSpeech] which internally awaits
///   only keyword extraction (fast, sync) — T5 grammar is skipped during calls
///   to avoid blocking the UI event loop.
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

  DetectionProvider? _detection;

  // ── Zero-rebuild notifiers ─────────────────────────────────────────────────
  /// Updated every second without calling notifyListeners().
  /// Widgets that only need the timer subscribe to this directly.
  final ValueNotifier<Duration> callDurationNotifier =
      ValueNotifier(Duration.zero);

  /// Updated on every STT partial result without calling notifyListeners().
  /// Only the transcript text widget subscribes to this.
  final ValueNotifier<String> transcriptNotifier = ValueNotifier('');

  /// Updated when a final STT result produces sign segments.
  final ValueNotifier<List<SignImageSegment>> signSegmentsNotifier =
      ValueNotifier([]);

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

  // Legacy getters kept for call screen compatibility (backed by notifiers now)
  String get remoteTranscript => transcriptNotifier.value;
  List<SignImageSegment> get translatedSignSegments =>
      signSegmentsNotifier.value;

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

      if (callType == 'video') {
        _detection?.enterCallModeVideoOnly();
      } else {
        _detection?.enterCallMode();
      }
      unawaited(_startRemoteStt());

      notifyListeners(); // one notify: state → active
    };

    _service.onCallEnded = () {
      final wasVideo = _currentCallType == 'video';
      _status = WebRtcCallStatus.ended;
      _detection?.exitCallMode();
      _detection?.onSentenceForCall = null;
      if (wasVideo && _userRole == 'deaf' && _detection != null) {
        unawaited(_detection!.restoreCameraAfterWebRtc());
      }
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
  }

  // ── Call timer — ValueNotifier, no notifyListeners() ──────────────────────
  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != WebRtcCallStatus.active) return;
      // Increment ValueNotifier directly — zero provider rebuilds.
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

        if (!isFinal || text.trim().isEmpty) return;
        // Fire-and-forget sign translation; runs async, never blocks video.
        unawaited(_updateSignTranslation(text));
      };

      _remoteStt.onStopped = () {
        // No notifyListeners here either — isRemoteListening badge uses Selector.
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

  // ── Sign translation — async, never blocks video ───────────────────────────
  Future<void> _updateSignTranslation(String text) async {
    if (_detection == null || _userRole != 'deaf') return;
    // processCallerSpeech is async (may await T5 grammar).
    // Result goes to ValueNotifier — zero provider rebuilds.
    await _detection!.processCallerSpeech(text);
    signSegmentsNotifier.value =
        List<SignImageSegment>.from(_detection!.signImageSegments);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  void setDetectionProvider(DetectionProvider detection) {
    if (_detection == detection) return;
    _detection = detection;
  }

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
    if (_currentCallType == 'video' && _detection != null) {
      await _detection!.releaseCameraForWebRtc();
    }
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
    final wasVideo = _currentCallType == 'video';
    _service.endCall();
    _detection?.exitCallMode();
    _detection?.onSentenceForCall = null;
    if (wasVideo && _userRole == 'deaf' && _detection != null) {
      unawaited(_detection!.restoreCameraAfterWebRtc());
    }
    unawaited(_stopRemoteStt());
    _stopCallTimer();
    _resetAfterCall();
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
    signSegmentsNotifier.value = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    callDurationNotifier.dispose();
    transcriptNotifier.dispose();
    signSegmentsNotifier.dispose();
    unawaited(_remoteStt.stopListening());
    _remoteStt.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _service.dispose();
    super.dispose();
  }
}
