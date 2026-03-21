class AppConfig {
  static const String appTitle = 'SYNAPSE';

  static const double gestureConfidenceThreshold = 0.50;
  static const Duration duplicateSuppression = Duration(milliseconds: 600);
  static const Duration wordBoundary = Duration(milliseconds: 1500);

  // T5 grammar model assets (bundled in APK — no download required)
  static const String t5EncoderAsset = 'assets/models/t5_encoder.tflite';
  static const String t5DecoderAsset = 'assets/models/t5_decoder.tflite';
  static const String t5VocabAsset = 'assets/models/t5_vocab.txt';
}
