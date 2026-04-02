import 'package:flutter/material.dart';

class AppConfig {
  // Onboarding color theme
  static const Color obBackground = Color(0xFF11181C);
  static const Color obPrimary = Color(0xFF95DE28);
  static const Color obPrimaryDark = Color(0xFF6CB61F);
  static const Color obAccentBlue = Color(0xFF42C68C);
  static const Color obCard = Color(0xFF182227);
  static const Color obBorder = Color(0xFF2A353B);
  static const Color obTextPrimary = Color(0xFFF3F7F1);
  static const Color obTextSecondary = Color(0xFF8FA0A8);
  static const String appTitle = 'VAANI';

  static const double gestureConfidenceThreshold = 0.50;

  // Keep duplicate suppression short so letter streaming feels responsive.
  static const Duration duplicateSuppression = Duration(milliseconds: 700);

  // Commit quickly after hand pause for near-instant phrase generation/speech.
  static const Duration noHandSentenceTrigger = Duration(milliseconds: 1200);

  // OpenRouter LLM
  static const String openRouterModel = 'qwen/qwen3-8b';
  static const String openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const int openRouterTimeoutMs = 5000;
  static const bool preferCloudSentenceGeneration = true;
  static const int cloudSentenceMaxWaitMs = 2200;
  // Hard kill switch for all cloud NLP calls (OpenRouter, etc.).
  // Keep true for privacy-first / offline-only deployments.
  static const bool strictOfflineMode = true;
  static const bool watchOfflineOnly = true;
  static const bool watchPreferSystemAudio = true;

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
  // Pi creates a hotspot — its gateway IP is always 192.168.4.1
  static const String hwSocketUrl = 'http://192.168.0.102:5000';
  static const String hwSsid = 'VAANI';
  static const String hwDeviceName = 'VAANI-HW';
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
  static const String webrtcBackendUrl = 'https://synapse-backend-wmmy.onrender.com';
  static const Map<String, dynamic> webrtcIceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };
}


