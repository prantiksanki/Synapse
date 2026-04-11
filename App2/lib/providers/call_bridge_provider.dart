import 'package:flutter/foundation.dart';
import '../services/call_bridge_service.dart';
import '../services/speech_service.dart';
import '../widgets/sign_image_display.dart';
import 'detection_provider.dart';

/// Orchestrates the call feature between Flutter and Android.
///
/// When a call is active:
///  - DetectionProvider.enterCallMode() suppresses its own STT.
///  - This provider runs a second [SpeechService] to transcribe the caller.
///  - Completed sign sentences from DetectionProvider are spoken via TTS
///    into the call (speakForCall on the native side).
///  - When TTS finishes (tts_done event), caller STT re-engages.
class CallBridgeProvider extends ChangeNotifier {
  final CallBridgeService _bridge = CallBridgeService();
  final SpeechService _callerStt = SpeechService();

  DetectionProvider? _detection;

  bool _isTtsSpeaking = false;
  String _callerTranscript = '';
  String _lastSpoken = '';
  int _sttFailCount = 0;
  bool _startingCallerStt = false;

  PhoneCallState get callState => _bridge.callState;
  String get callerNumber => _bridge.callerNumber;
  bool get isTtsSpeaking => _isTtsSpeaking;
  String get callerTranscript => _callerTranscript;
  String get lastSpoken => _lastSpoken;
  bool get isCallerSttListening => _callerStt.isListening;
  SpeechListenStatus get callerListenStatus {
    if (_isTtsSpeaking) return SpeechListenStatus.processing;
    return _callerStt.isListening
        ? SpeechListenStatus.listening
        : SpeechListenStatus.idle;
  }

  CallBridgeProvider() {
    _bridge.onStateChanged = _onBridgeStateChanged;
    _bridge.onTtsDone = _onTtsDone;
    _bridge.initialize();
  }

  // ── DetectionProvider wiring ──────────────────────────────────────────────

  void attach(DetectionProvider detection) {
    if (_detection == detection) return;
    _detection?.removeSentenceForCallListener(_onSentenceForCall);
    _detection = detection;
    detection.addSentenceForCallListener(_onSentenceForCall);
  }

  // ── Call state ────────────────────────────────────────────────────────────

  void _onBridgeStateChanged() {
    switch (_bridge.callState) {
      case PhoneCallState.active:
        _detection?.enterCallMode();
        _bridge.routeForStt();
        _startCallerStt();
        break;
      case PhoneCallState.idle:
      case PhoneCallState.ended:
        _detection?.exitCallMode();
        _stopCallerStt();
        _isTtsSpeaking = false;
        _callerTranscript = '';
        _startingCallerStt = false;
        break;
      case PhoneCallState.ringing:
        break;
    }
    notifyListeners();
  }

  // ── Caller STT (transcribes what the caller says) ─────────────────────────

  Future<void> _startCallerStt() async {
    if (_bridge.callState != PhoneCallState.active) return;
    if (_isTtsSpeaking || _callerStt.isListening || _startingCallerStt) return;
    _startingCallerStt = true;
    try {
      final ready = await _callerStt.initialize();
      if (!ready) return;
      _callerStt.onResult = (text, isFinal) {
        _sttFailCount = 0; // reset backoff on any successful result
        _callerTranscript = text;
        notifyListeners();
        if (isFinal) _detection?.processCallerSpeech(text);
      };
      _callerStt.onStopped = () {
        // Keep looping while call is active and not speaking TTS
        if (_bridge.callState == PhoneCallState.active && !_isTtsSpeaking) {
          _sttFailCount++;
          // Exponential backoff: 300ms, 600ms, 900ms, 1200ms, 1500ms (max)
          final delay = Duration(milliseconds: 300 * _sttFailCount.clamp(1, 5));
          Future.delayed(delay, _startCallerStt);
        }
      };
      await _callerStt.startListening();
      notifyListeners();
    } finally {
      _startingCallerStt = false;
    }
  }

  Future<void> _stopCallerStt() async {
    _sttFailCount = 0;
    _startingCallerStt = false;
    await _callerStt.stopListening();
    notifyListeners();
  }

  // ── Sign → TTS (deaf user signs, caller hears it) ─────────────────────────

  void _onSentenceForCall(String sentence) {
    if (sentence.trim().isEmpty) return;
    if (_bridge.callState != PhoneCallState.active) return;
    _relaySentenceToCaller(sentence);
  }

  Future<void> _relaySentenceToCaller(String sentence) async {
    _lastSpoken = sentence;
    _isTtsSpeaking = true;
    notifyListeners();

    // Pause caller STT while relay speech is playing to avoid self-capture.
    await _callerStt.stopListening();
    await _bridge.routeForTts();
    await _bridge.speakForCall(sentence);
  }

  // ── TTS done (native fires tts_done event) ────────────────────────────────

  void _onTtsDone() {
    _isTtsSpeaking = false;
    notifyListeners();
    // Re-engage caller STT
    if (_bridge.callState == PhoneCallState.active) {
      // Switch audio back to caller relay capture mode.
      _bridge.routeForStt();
      _startCallerStt();
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> startCallMode() => _bridge.startCallMode();
  Future<void> stopCallMode()  => _bridge.stopCallMode();

  @override
  void dispose() {
    _detection?.removeSentenceForCallListener(_onSentenceForCall);
    _bridge.dispose();
    _callerStt.stopListening();
    _callerStt.dispose();
    super.dispose();
  }
}
