import 'package:flutter/services.dart';

class TtsService {
  static const MethodChannel _channel = MethodChannel('synapse/llm');

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _channel.invokeMethod<void>('speak', {'text': text});
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stopSpeaking');
  }
}
