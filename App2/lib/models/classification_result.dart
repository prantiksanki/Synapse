/// Represents the result of a gesture classification.
class ClassificationResult {
  final String label;
  final int labelIndex;
  final double confidence;
  final Map<String, double> probabilities;

  const ClassificationResult({
    required this.label,
    required this.labelIndex,
    required this.confidence,
    required this.probabilities,
  });

  @override
  String toString() {
    return 'ClassificationResult(label: $label, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
  }

  /// Get confidence as percentage string
  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  /// Check if confidence is above threshold
  bool isConfident({double threshold = 0.5}) => confidence >= threshold;
}
