import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/classification_result.dart';
import '../models/gesture_result.dart';
import '../models/hand_landmark.dart';
import '../models/llm_generation_result.dart';
import '../models/model_download_state.dart';
import '../models/word_buffer_state.dart';
import '../services/camera_service.dart';
import '../services/hand_landmark_service.dart';
import '../services/landmark_processor.dart';
import '../services/llm_service.dart';
import '../services/model_downloader.dart';
import '../services/sign_classifier.dart';
import '../services/tts_service.dart';
import '../services/word_buffer.dart';

enum DetectionState { uninitialized, initializing, ready, detecting, error }

class DetectionProvider extends ChangeNotifier {
  static const String unsupportedPlatformMessage =
      'Real-time sign language detection is currently supported on Android only. '
      'Run this app on an Android device or emulator with camera access.';

  final CameraService _cameraService = CameraService();
  final HandLandmarkService _handLandmarkService = HandLandmarkService();
  final SignClassifier _signClassifier = SignClassifier();
  final WordBufferService _wordBufferService = WordBufferService();
  final ModelDownloader _modelDownloader = ModelDownloader();
  final LlmService _llmService = LlmService();
  final TtsService _ttsService = TtsService();

  DetectionState _state = DetectionState.uninitialized;
  HandLandmarks? _currentLandmarks;
  ClassificationResult? _currentResult;
  GestureResult? _currentGesture;
  String? _errorMessage;
  ModelDownloadState _modelDownloadState = const ModelDownloadState.idle();
  LlmGenerationResult _generationResult = const LlmGenerationResult.idle();
  int _generationRequestId = 0;
  bool _isGeneratingSentence = false;

  // FPS tracking
  int _frameCount = 0;
  double _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Getters
  DetectionState get state => _state;
  HandLandmarks? get currentLandmarks => _currentLandmarks;
  ClassificationResult? get currentResult => _currentResult;
  GestureResult? get currentGesture => _currentGesture;
  String? get errorMessage => _errorMessage;
  double get fps => _fps;
  CameraController? get cameraController => _cameraService.controller;
  bool get isInitialized =>
      _state == DetectionState.ready || _state == DetectionState.detecting;
  bool get isDetecting => _state == DetectionState.detecting;
  bool get isPlatformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  WordBufferState get wordBufferState => _wordBufferService.state;
  ModelDownloadState get modelDownloadState => _modelDownloadState;
  LlmGenerationResult get generationResult => _generationResult;
  bool get isGeneratingSentence => _isGeneratingSentence;
  bool get isLlmReady => _modelDownloadState.isLoaded;

  Future<void> initialize() async {
    if (_state == DetectionState.initializing) return;

    _state = DetectionState.initializing;
    _errorMessage = null;
    notifyListeners();

    try {
      if (!isPlatformSupported) {
        throw UnsupportedError(unsupportedPlatformMessage);
      }

      // Initialize camera first to get sensor orientation
      await _cameraService.initialize();

      // Initialize hand landmarker with sensor orientation
      _handLandmarkService.initialize(
        sensorOrientation: _cameraService.sensorOrientation,
      );

      // Initialize classifier
      await _signClassifier.initialize();

      _state = DetectionState.ready;
      notifyListeners();
      unawaited(_prepareLlm());
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e is UnsupportedError
          ? unsupportedPlatformMessage
          : e.toString();
      notifyListeners();
    }
  }

  Future<void> startDetection() async {
    if (_state != DetectionState.ready) return;

    try {
      _state = DetectionState.detecting;
      _frameCount = 0;
      _lastFpsUpdate = DateTime.now();
      notifyListeners();

      await _cameraService.startImageStream(_onCameraImage);
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopDetection() async {
    if (_state != DetectionState.detecting) return;

    try {
      await _cameraService.stopImageStream();
      _state = DetectionState.ready;
      _currentLandmarks = null;
      _currentResult = null;
      notifyListeners();
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _onCameraImage(CameraImage image) {
    // Process the camera image (synchronous)
    final landmarks = _handLandmarkService.processImage(image);

    // Update FPS counter
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;
    if (elapsed >= 1000) {
      _fps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    if (landmarks == null || landmarks.length != 21) {
      _currentLandmarks = null;
      _currentResult = null;
      _currentGesture = null;
      final finalizedPhrase = _wordBufferService.ingest(null);
      if (finalizedPhrase != null) {
        unawaited(_generateSentence(finalizedPhrase));
      }
      notifyListeners();
      return;
    }

    // Update landmarks
    _currentLandmarks = HandLandmarks.fromList(landmarks);

    // Preprocess and classify
    try {
      final preprocessed = LandmarkProcessor.preProcessNormalizedLandmarks(
        landmarks,
      );
      final result = _signClassifier.classify(preprocessed);
      _currentResult = result;
      if (result != null) {
        debugPrint(
          'Classified: ${result.label} conf=${result.confidence.toStringAsFixed(2)}',
        );
        _currentGesture = GestureResult(
          label: result.label,
          labelIndex: result.labelIndex,
          confidence: result.confidence,
          probabilities: result.probabilities,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
        final finalizedPhrase = _wordBufferService.ingest(_currentGesture);
        if (finalizedPhrase != null) {
          unawaited(_generateSentence(finalizedPhrase));
        }
      } else {
        _currentGesture = null;
        final finalizedPhrase = _wordBufferService.ingest(null);
        if (finalizedPhrase != null) {
          unawaited(_generateSentence(finalizedPhrase));
        }
      }
    } catch (e) {
      debugPrint('Classification error: $e');
      _currentResult = null;
      _currentGesture = null;
    }

    notifyListeners();
  }

  Future<void> speakLatestSentence() async {
    if (!_generationResult.hasSentence) return;
    try {
      await _ttsService.speak(_generationResult.sentence);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  Future<void> _prepareLlm() async {
    try {
      _modelDownloadState = const ModelDownloadState(
        status: ModelDownloadStatus.checking,
      );
      notifyListeners();

      // Check that the native llama_bridge.so was compiled into the APK.
      final nativeReady = await _llmService.isNativeLibLoaded();
      if (!nativeReady) {
        _modelDownloadState = const ModelDownloadState(
          status: ModelDownloadStatus.error,
          error:
              'Native llama_bridge library not found in APK. '
              'Rebuild the app with NDK enabled so libllama_bridge.so is included.',
        );
        notifyListeners();
        return;
      }

      if (await _llmService.isModelLoaded()) {
        _modelDownloadState = ModelDownloadState(
          status: ModelDownloadStatus.loaded,
          localPath: await _modelDownloader.resolveModelPath(),
        );
        notifyListeners();
        return;
      }

      final modelExists = await _modelDownloader.modelExists();
      if (!modelExists) {
        _modelDownloadState = const ModelDownloadState(
          status: ModelDownloadStatus.missing,
        );
        notifyListeners();

        final file = await _modelDownloader.downloadModel(
          onProgress: (received, total) {
            _modelDownloadState = ModelDownloadState(
              status: ModelDownloadStatus.downloading,
              bytesDownloaded: received,
              totalBytes: total,
              progress: total > 0 ? received / total : 0,
            );
            notifyListeners();
          },
        );

        _modelDownloadState = ModelDownloadState(
          status: ModelDownloadStatus.ready,
          localPath: file.path,
        );
        notifyListeners();
      }

      final modelPath = await _modelDownloader.resolveModelPath();
      _modelDownloadState = ModelDownloadState(
        status: ModelDownloadStatus.loading,
        localPath: modelPath,
      );
      notifyListeners();

      final loaded = await _llmService.loadModel(modelPath);
      _modelDownloadState = ModelDownloadState(
        status: loaded ? ModelDownloadStatus.loaded : ModelDownloadStatus.error,
        localPath: modelPath,
        error: loaded ? null : 'Unable to load the local language model.',
      );
      notifyListeners();
    } catch (e) {
      _modelDownloadState = ModelDownloadState(
        status: ModelDownloadStatus.error,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  /// Force-commit the current buffer and generate a sentence immediately.
  /// Useful as a manual "send" button on the UI.
  Future<void> forceGenerate() async {
    final phrase = _wordBufferService.forceCommit();
    if (phrase != null && phrase.trim().isNotEmpty) {
      unawaited(_generateSentence(phrase));
    }
  }

  Future<void> _generateSentence(String phrase) async {
    if (phrase.trim().isEmpty) return;

    final requestId = ++_generationRequestId;
    _isGeneratingSentence = true;
    notifyListeners();

    LlmGenerationResult result;
    if (isLlmReady) {
      // Use on-device LLM (llama.cpp or template engine via platform channel).
      result = await _llmService.generateSentence(phrase);
    } else {
      // LLM not loaded yet — produce a sentence immediately via template engine
      // so the user always sees output.
      final sw = Stopwatch()..start();
      final sentence = _templateFallback(phrase);
      sw.stop();
      result = LlmGenerationResult(
        inputTokens: phrase,
        sentence: sentence,
        latencyMs: sw.elapsedMilliseconds,
        source: 'Dart fallback',
      );
    }

    if (requestId != _generationRequestId) return;

    _generationResult = result;
    _isGeneratingSentence = false;
    notifyListeners();
  }

  /// Dart-side fallback when TinyLlama isn't loaded yet.
  /// Produces a first-person sentence so output is always meaningful.
  String _templateFallback(String input) {
    final tokens = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '';
    final joined = tokens.map((t) => t.toLowerCase()).join(', ');
    if (tokens.length == 1) {
      return 'I want to say: ${tokens.first.toLowerCase()}.';
    }
    return 'I need help with: $joined.';
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _handLandmarkService.dispose();
    _signClassifier.dispose();
    unawaited(_llmService.releaseModel());
    unawaited(_ttsService.stop());
    super.dispose();
  }
}
