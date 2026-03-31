import 'dart:async';
import 'package:flutter/services.dart';

class TtsService {
  static const _channel = MethodChannel('synapse/llm');
  static const _callChannel = MethodChannel('synapse/call_control');
  static const _callEvents = EventChannel('synapse/call_events');

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _channel.invokeMethod<void>('speak', {'text': text});
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stopSpeaking');
  }

  /// Speak during a WebRTC call. Uses the native speakForCall path which:
  /// sets MODE_IN_COMMUNICATION + speakerphone ON, plays TTS, fires tts_done.
  /// Returns only after TTS finishes (or 10s safety timeout).
  Future<void> speakForCall(String text) async {
    if (text.trim().isEmpty) return;

    final completer = Completer<void>();
    StreamSubscription<dynamic>? sub;

    // Subscribe BEFORE invokeMethod so tts_done can never arrive before listener is ready.
    sub = _callEvents.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map<dynamic, dynamic>;
        if (map['event'] == 'tts_done' && !completer.isCompleted) {
          completer.complete();
          sub?.cancel();
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
        sub?.cancel();
      },
    );

    await _callChannel.invokeMethod<void>('speakForCall', {'text': text});

    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () { sub?.cancel(); },
    );
  }
}
