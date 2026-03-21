// llm_service.dart — Dart-side bridge to the on-device TinyLlama LLM.
//
// Communicates with LlamaPlugin (Kotlin) via the MethodChannel
// "com.synapse.app/llama". The native side loads the GGUF model into memory
// via llama.cpp (or the stub) and performs text generation on a background
// thread so the Flutter UI is never blocked.
//
// Typical flow:
//   1. llmService.loadModel(path)          — once, after download
//   2. llmService.generateSentence(words)  — each time words are ready
//   3. llmService.release()                — on app dispose

import 'dart:developer' as dev;

import 'package:flutter/services.dart';

/// Dart wrapper for the on-device TinyLlama inference engine.
class LlmService {
  // -------------------------------------------------------------------------
  // Platform channel
  // -------------------------------------------------------------------------

  static const _channel = MethodChannel('com.synapse.app/llama');

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  bool _isModelLoaded = false;

  /// Whether the model has been successfully loaded into native memory.
  bool get isModelLoaded => _isModelLoaded;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Load the GGUF model at [modelPath] into the native llama.cpp context.
  ///
  /// Returns true on success. Must be called before [generateSentence].
  Future<bool> loadModel(String modelPath) async {
    try {
      dev.log('Loading LLM model from: $modelPath', name: 'LlmService');
      final result = await _channel.invokeMethod<bool>(
        'loadModel',
        {'modelPath': modelPath},
      );
      _isModelLoaded = result ?? false;
      dev.log('Model load result: $_isModelLoaded', name: 'LlmService');
      return _isModelLoaded;
    } on PlatformException catch (e) {
      dev.log('loadModel PlatformException: ${e.message}', name: 'LlmService', level: 900);
      _isModelLoaded = false;
      return false;
    } on MissingPluginException {
      dev.log(
        'LlamaPlugin not registered — running without LLM.',
        name: 'LlmService',
      );
      _isModelLoaded = false;
      return false;
    } catch (e) {
      dev.log('loadModel unexpected error: $e', name: 'LlmService', level: 900);
      _isModelLoaded = false;
      return false;
    }
  }

  /// Convert a list of detected sign-language keywords into a natural sentence.
  ///
  /// [signWords] is a list of completed words/signs, e.g. ['HELP', 'PLEASE', 'WATER'].
  ///
  /// The words are joined and passed to TinyLlama with an instruction prompt.
  /// If the model is not loaded, the raw keywords are joined and returned as-is.
  Future<String> generateSentence(List<String> signWords) async {
    if (signWords.isEmpty) return '';

    final joined = signWords.join(' ');

    if (!_isModelLoaded) {
      dev.log(
        'generateSentence: model not loaded, returning raw keywords.',
        name: 'LlmService',
      );
      return joined;
    }

    try {
      dev.log('Generating sentence for: $joined', name: 'LlmService');
      final result = await _channel.invokeMethod<String>(
        'generateSentence',
        {'signWords': joined},
      );
      final sentence = result?.trim() ?? joined;
      dev.log('Generated: "$sentence"', name: 'LlmService');
      return sentence.isEmpty ? joined : sentence;
    } on PlatformException catch (e) {
      dev.log('generateSentence PlatformException: ${e.message}',
          name: 'LlmService', level: 900);
      return joined;
    } on MissingPluginException {
      dev.log(
        'LlamaPlugin not registered — returning raw keywords.',
        name: 'LlmService',
      );
      return joined;
    } catch (e) {
      dev.log('generateSentence unexpected error: $e',
          name: 'LlmService', level: 900);
      return joined;
    }
  }

  /// Release native model resources.
  ///
  /// Should be called when the app is disposed or the user explicitly
  /// unloads the model to free memory.
  Future<void> release() async {
    if (!_isModelLoaded) return;
    try {
      await _channel.invokeMethod<void>('releaseModel');
      dev.log('LLM model released.', name: 'LlmService');
    } on PlatformException catch (e) {
      dev.log('release PlatformException: ${e.message}',
          name: 'LlmService', level: 900);
    } on MissingPluginException {
      // Nothing to release if the plugin was never registered
    } catch (e) {
      dev.log('release unexpected error: $e', name: 'LlmService', level: 900);
    } finally {
      _isModelLoaded = false;
    }
  }
}
