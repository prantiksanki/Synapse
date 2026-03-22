class AppConfig {
  static const String appTitle = 'SYNAPSE';

  static const double gestureConfidenceThreshold = 0.50;
  static const Duration duplicateSuppression = Duration(milliseconds: 600);
  static const Duration wordBoundary = Duration(milliseconds: 1500);

  // T5 grammar model downloaded on first launch from Hugging Face.
  static const String _hfBase =
      'https://huggingface.co/TeXlyre/grammar-t5-small-onnx/resolve/main/onnx';

  static const String t5EncoderUrl = '$_hfBase/encoder_model.onnx';
  static const String t5DecoderUrl = '$_hfBase/decoder_model.onnx';

  static const String _hfBaseRoot =
      'https://huggingface.co/TeXlyre/grammar-t5-small-onnx/resolve/main';
  static const String t5VocabUrl = '$_hfBaseRoot/tokenizer.json';

  static const String t5EncoderFileName = 'encoder_model.onnx';
  static const String t5DecoderFileName = 'decoder_model.onnx';
  static const String t5VocabFileName = 'tokenizer.json';

  static const String t5ModelSizeLabel = '~95 MB';

  // Speech / sign-image mode
  static const Duration handAbsenceThreshold = Duration(milliseconds: 1500);
  static const Duration speechRestartDelay = Duration(milliseconds: 300);
  static const String signImageManifestPath = 'assets/sign_images/manifest.json';
  static const double signImageTileSize = 64.0;
  static const double wordSpaceWidth = 20.0;
}
