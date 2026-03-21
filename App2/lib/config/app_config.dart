class AppConfig {
  static const String appTitle = 'SYNAPSE';

  static const double gestureConfidenceThreshold = 0.50;
  static const Duration duplicateSuppression = Duration(milliseconds: 600);
  static const Duration wordBoundary = Duration(milliseconds: 1500);

  static const String modelDirectoryName = 'models';

  // Filename that the GGUF will be saved as on device
  static const String llamaModelFileName =
      'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  // Direct download URL — TinyLlama 1.1B Chat Q4_K_M (~670 MB)
  static const String llamaModelUrl =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';
}

