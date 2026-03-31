class LlmGenerationResult {
  final String inputTokens;
  final String sentence;
  final int latencyMs;
  final String source;
  final String? error;

  const LlmGenerationResult({
    required this.inputTokens,
    required this.sentence,
    required this.latencyMs,
    required this.source,
    this.error,
  });

  const LlmGenerationResult.idle()
    : inputTokens = '',
      sentence = '',
      latencyMs = 0,
      source = '',
      error = null;

  bool get hasSentence => sentence.trim().isNotEmpty;
}
