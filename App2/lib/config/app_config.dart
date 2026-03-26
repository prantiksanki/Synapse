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

  // Hardware device (Raspberry Pi)
  static const String hwSocketUrl = 'http://192.168.0.102:5000';
  static const String hwSsid = 'SYNAPSE';
  static const String hwDeviceName = 'SYNAPSE-HW';
  static const Duration hwReconnectDelay = Duration(seconds: 3);
  static const Duration hwPingInterval = Duration(seconds: 5);
  static const int frameQueueMaxDepth = 3;
  static const int hwStreamFps = 30;
  static const int hwStreamQuality = 65;

  // Speech / sign-image mode
  static const Duration handAbsenceThreshold = Duration(milliseconds: 1500);
  static const Duration speechRestartDelay = Duration(milliseconds: 300);
  static const String signImageManifestPath = 'assets/sign_images/manifest.json';
  static const double signImageTileSize = 64.0;
  static const double wordSpaceWidth = 20.0;

  // Phone call bridge
  static const String callControlChannel = 'synapse/call_control';
  static const String callEventsChannel = 'synapse/call_events';
  static const Duration callTtsDelay = Duration(milliseconds: 500);

  // WebRTC calling system
  // Change this to your PC's local IP address (run `ipconfig` on Windows)
  static const String webrtcBackendUrl = 'http://192.168.0.100:3000';
  static const Map<String, dynamic> webrtcIceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };
}