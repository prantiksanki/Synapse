class GestureResult {
  final String label;
  final int labelIndex;
  final double confidence;
  final Map<String, double> probabilities;
  final int timestampMs;

  const GestureResult({
    required this.label,
    required this.labelIndex,
    required this.confidence,
    required this.probabilities,
    required this.timestampMs,
  });

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';
}
