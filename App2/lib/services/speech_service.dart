import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechStatus { unavailable, idle, listening, error }

/// Wraps the [SpeechToText] package with a simple callback-based API.
class SpeechService {
  final SpeechToText _stt = SpeechToText();

  static const _audioChannel = MethodChannel('synapse/audio_utils');

  SpeechStatus _status = SpeechStatus.idle;
  String? _lastError;
  // Whether the current/last session was started with mute enabled.
  bool _muteEnabled = false;

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

  /// Start listening — mutes Android beep tones during the session.
  Future<void> startListening() async {
    if (_status == SpeechStatus.unavailable) return;
    if (_stt.isListening) return;
    _muteEnabled = true;
    await _muteBeep();
    await _doListen();
  }

  /// Start listening WITHOUT muting system beeps or grabbing exclusive audio
  /// focus. Use this when other audio (e.g. a video) is already playing so
  /// that the video is not paused/interrupted.
  Future<void> startListeningSilent() async {
    if (_status == SpeechStatus.unavailable) return;
    if (_stt.isListening) return;
    _muteEnabled = false;
    await _doListen();
  }

  Future<void> _doListen() async {
    _status = SpeechStatus.listening;
    await _stt.listen(
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          onResult?.call(text, result.finalResult);
        }
      },
      listenFor: const Duration(seconds: 120),
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
    if (_muteEnabled) await _unmuteBeep();
    _muteEnabled = false;
  }

  /// Cancel and discard the current recognition session.
  Future<void> cancelListening() async {
    await _stt.cancel();
    _status = SpeechStatus.idle;
    if (_muteEnabled) await _unmuteBeep();
    _muteEnabled = false;
  }

  void _onError(SpeechRecognitionError error) {
    _lastError = error.errorMsg;
    _status = SpeechStatus.error;
    debugPrint('SpeechService error: ${error.errorMsg}');
    if (_muteEnabled) _unmuteBeep();
    _muteEnabled = false;
    onStopped?.call();
  }

  void _onStatus(String status) {
    debugPrint('SpeechService status: $status');
    if (status == 'done' || status == 'notListening') {
      _status = SpeechStatus.idle;
      if (_muteEnabled) _unmuteBeep();
      _muteEnabled = false;
      onStopped?.call();
    }
  }

  Future<void> _muteBeep() async {
    try {
      await _audioChannel.invokeMethod('muteBeep');
    } catch (_) {}
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
