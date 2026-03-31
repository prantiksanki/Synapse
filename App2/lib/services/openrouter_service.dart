import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/llm_generation_result.dart';

/// Calls OpenRouter Chat Completions API to form coherent words/sentences
/// from a sequence of detected sign-language letters.
class OpenRouterService {
  static const String _systemPrompt =
      'The input is stream of letters, you have to generate meaningful sentence or word using those letters. Do not give any redundant text. Only the output.';

  String? get _apiKey => dotenv.env['OPENROUTER_API_KEY'];

  /// Attempt to form a sentence from [rawTokens] (space-separated letters).
  ///
  /// Returns an [LlmGenerationResult] with `source = 'openrouter'` on success,
  /// or `source = 'fallback'` when the API call fails.
  Future<LlmGenerationResult> formSentence(String rawTokens) async {
    final stopwatch = Stopwatch()..start();

    // Strip special tokens before sending.
    final cleaned = rawTokens
        .split(' ')
        .where((t) => t.isNotEmpty && t != 'DELETE' && t != 'SPACE')
        .join(' ');

    if (cleaned.trim().isEmpty) {
      return LlmGenerationResult(
        inputTokens: rawTokens,
        sentence: '',
        latencyMs: 0,
        source: 'fallback',
      );
    }

    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[OpenRouter] No API key found in .env');
      return _fallback(rawTokens, cleaned, stopwatch);
    }

    // Try up to 2 attempts (1 initial + 1 retry).
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(AppConfig.openRouterUrl),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://synapse.app',
                'X-Title': 'Synapse Sign Language',
              },
              body: jsonEncode({
                'model': AppConfig.openRouterModel,
                'temperature': 0.2,
                'max_tokens': 60,
                'messages': [
                  {'role': 'system', 'content': _systemPrompt},
                  {'role': 'user', 'content': cleaned},
                ],
              }),
            )
            .timeout(
              Duration(milliseconds: AppConfig.openRouterTimeoutMs),
            );

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final choices = body['choices'] as List<dynamic>?;
          final text = choices != null && choices.isNotEmpty
              ? ((choices[0] as Map<String, dynamic>)['message']
                      as Map<String, dynamic>)['content']
                  ?.toString()
                  .trim()
              : null;

          stopwatch.stop();
          debugPrint(
            '[OpenRouter] Response in ${stopwatch.elapsedMilliseconds}ms: $text',
          );

          return LlmGenerationResult(
            inputTokens: rawTokens,
            sentence: text ?? cleaned.replaceAll(' ', ''),
            latencyMs: stopwatch.elapsedMilliseconds,
            source: 'openrouter',
          );
        }

        // Transient server error — retry after backoff.
        if (response.statusCode >= 500 && attempt == 0) {
          debugPrint(
            '[OpenRouter] Server error ${response.statusCode}, retrying...',
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        // Non-retryable error.
        debugPrint(
          '[OpenRouter] Error ${response.statusCode}: ${response.body}',
        );
        break;
      } catch (e) {
        debugPrint('[OpenRouter] Request failed (attempt $attempt): $e');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
      }
    }

    return _fallback(rawTokens, cleaned, stopwatch);
  }

  /// Simple fallback: concatenate letters.
  LlmGenerationResult _fallback(
    String rawTokens,
    String cleaned,
    Stopwatch sw,
  ) {
    sw.stop();
    final concatenated = cleaned.replaceAll(' ', '');
    debugPrint('[OpenRouter] Falling back to concatenation: $concatenated');
    return LlmGenerationResult(
      inputTokens: rawTokens,
      sentence: concatenated,
      latencyMs: sw.elapsedMilliseconds,
      source: 'fallback',
    );
  }
}
