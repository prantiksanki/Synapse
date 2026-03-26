import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechStatus { unavailable, idle, listening, error }

/// Wraps the [SpeechToText] package with a simple callback-based API.
///
/// Usage:
/// ```dart
/// final svc = SpeechService();
/// await svc.initialize();
/// svc.onResult = (text, isFinal) { ... };
/// svc.onStopped = () { ... };
/// await svc.startListening();
/// ```
class SpeechService {
  final SpeechToText _stt = SpeechToText();

  // Channel to the native side for muting/unmuting the STT beep sounds.
  static const _audioChannel = MethodChannel('synapse/audio_utils');

  SpeechStatus _status = SpeechStatus.idle;
  String? _lastError;

  SpeechStatus get status => _status;
  String? get lastError => _lastError;
  bool get isListening => _stt.isListening;

  /// Fired on each recognition result (partial or final).
  void Function(String text, bool isFinal)? onResult;

  /// Fired when listening stops for any reason (timeout, error, explicit stop).
  VoidCallback? onStopped;

  /// Initialise the speech recogniser. Returns true if the device supports STT.
  Future<bool> initialize() async {
    final available = await _stt.initialize(
      onError: _onError,
      onStatus: _onStatus,
      debugLogging: false,
    );
    _status = available ? SpeechStatus.idle : SpeechStatus.unavailable;
    return available;
  }

  /// Start listening. No-op if already listening or unavailable.
  Future<void> startListening() async {
    if (_status == SpeechStatus.unavailable) return;
    if (_stt.isListening) return;

    await _muteBeep();

    _status = SpeechStatus.listening;
    await _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          onResult?.call(text, result.finalResult);
        }
      },
      listenFor: const Duration(seconds: 120),
      // 5 s silence before auto-stop — gives user time to pause between words.
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  /// Stop listening gracefully.
  Future<void> stopListening() async {
    if (!_stt.isListening) return;
    await _stt.stop();
    _status = SpeechStatus.idle;
    await _unmuteBeep();
  }

  /// Cancel and discard the current recognition session.
  Future<void> cancelListening() async {
    await _stt.cancel();
    _status = SpeechStatus.idle;
    await _unmuteBeep();
  }

  void _onError(SpeechRecognitionError error) {
    _lastError = error.errorMsg;
    _status = SpeechStatus.error;
    debugPrint('SpeechService error: ${error.errorMsg}');
    _unmuteBeep();
    onStopped?.call();
  }

  void _onStatus(String status) {
    debugPrint('SpeechService status: $status');
    if (status == 'done' || status == 'notListening') {
      _status = SpeechStatus.idle;
      _unmuteBeep();
      onStopped?.call();
    }
  }

  // Silences Android UI tones during STT sessions.
  // The native side mutes STREAM_NOTIFICATION and STREAM_SYSTEM; add STREAM_RING
  // in case the platform is using it for STT start/stop tones.
  Future<void> _muteBeep() async {
    try {
      await _audioChannel.invokeMethod('muteBeep');
    } catch (_) {
      // Non-fatal — if the channel isn't set up, beeps will just play.
    }
  }

  Future<void> _unmuteBeep() async {
    try {
      await _audioChannel.invokeMethod('unmuteBeep');
    } catch (_) {}
  }

  void dispose() {
    _stt.cancel();
  }
}
