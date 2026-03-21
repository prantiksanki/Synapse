import 'package:flutter/services.dart';
import '../models/llm_generation_result.dart';

class LlmService {
  static const MethodChannel _channel = MethodChannel('synapse/llm');

  Future<bool> isModelLoaded() async {
    final loaded = await _channel.invokeMethod<bool>('isModelLoaded');
    return loaded ?? false;
  }

  Future<bool> isNativeLibLoaded() async {
    final loaded = await _channel.invokeMethod<bool>('isNativeLibLoaded');
    return loaded ?? false;
  }

  Future<bool> loadModel(String path) async {
    final loaded = await _channel.invokeMethod<bool>('loadModel', {
      'path': path,
    });
    return loaded ?? false;
  }

  Future<LlmGenerationResult> generateSentence(String inputTokens) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _channel.invokeMethod<dynamic>(
        'generateSentence',
        {'input': inputTokens},
      );
      stopwatch.stop();

      if (response is Map) {
        final data = Map<Object?, Object?>.from(response);
        return LlmGenerationResult(
          inputTokens: inputTokens,
          sentence: (data['sentence'] as String?) ?? '',
          latencyMs: stopwatch.elapsedMilliseconds,
          source: (data['source'] as String?) ?? 'TinyLlama',
          error: data['error'] as String?,
        );
      }

      return LlmGenerationResult(
        inputTokens: inputTokens,
        sentence: response as String? ?? '',
        latencyMs: stopwatch.elapsedMilliseconds,
        source: 'TinyLlama',
      );
    } catch (e) {
      stopwatch.stop();
      return LlmGenerationResult(
        inputTokens: inputTokens,
        sentence: '',
        latencyMs: stopwatch.elapsedMilliseconds,
        source: 'Generation error',
        error: e.toString(),
      );
    }
  }

  Future<bool> releaseModel() async {
    final released = await _channel.invokeMethod<bool>('releaseModel');
    return released ?? false;
  }
}
