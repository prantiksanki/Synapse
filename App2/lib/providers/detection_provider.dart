import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/classification_result.dart';
import '../models/gesture_result.dart';
import '../models/hand_landmark.dart';
import '../models/llm_generation_result.dart';
import '../models/word_buffer_state.dart';
import '../services/camera_service.dart';
import '../services/hand_landmark_service.dart';
import '../services/landmark_processor.dart';
import '../services/sign_classifier.dart';
import '../services/t5_grammar_service.dart';
import '../services/tts_service.dart';
import '../services/word_buffer.dart';

enum DetectionState { uninitialized, initializing, ready, detecting, error }

/// Status of the T5 grammar model loading.
enum GrammarModelStatus { loading, ready, error }

class DetectionProvider extends ChangeNotifier {
  static const String unsupportedPlatformMessage =
      'Real-time sign language detection is currently supported on Android only. '
      'Run this app on an Android device or emulator with camera access.';

  final CameraService _cameraService = CameraService();
  final HandLandmarkService _handLandmarkService = HandLandmarkService();
  final SignClassifier _signClassifier = SignClassifier();
  final WordBufferService _wordBufferService = WordBufferService();
  final T5GrammarService _grammarService = T5GrammarService();
  final TtsService _ttsService = TtsService();

  DetectionState _state = DetectionState.uninitialized;
  HandLandmarks? _currentLandmarks;
  ClassificationResult? _currentResult;
  GestureResult? _currentGesture;
  String? _errorMessage;

  GrammarModelStatus _grammarStatus = GrammarModelStatus.loading;
  String? _grammarLoadError;

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
  LlmGenerationResult get generationResult => _generationResult;
  bool get isGeneratingSentence => _isGeneratingSentence;

  GrammarModelStatus get grammarStatus => _grammarStatus;
  String? get grammarLoadError => _grammarLoadError;
  bool get isGrammarReady => _grammarStatus == GrammarModelStatus.ready;

  Future<void> initialize() async {
    if (_state == DetectionState.initializing) return;

    _state = DetectionState.initializing;
    _errorMessage = null;
    notifyListeners();

    try {
      if (!isPlatformSupported) {
        throw UnsupportedError(unsupportedPlatformMessage);
      }

      await _cameraService.initialize();

      _handLandmarkService.initialize(
        sensorOrientation: _cameraService.sensorOrientation,
      );

      await _signClassifier.initialize();

      _state = DetectionState.ready;
      notifyListeners();

      // Load T5 grammar model in background — UI still works via Dart fallback
      unawaited(_loadGrammarModel());
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e is UnsupportedError
          ? unsupportedPlatformMessage
          : e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadGrammarModel() async {
    _grammarStatus = GrammarModelStatus.loading;
    notifyListeners();

    await _grammarService.load();

    if (_grammarService.isReady) {
      _grammarStatus = GrammarModelStatus.ready;
      _grammarLoadError = null;
    } else {
      _grammarStatus = GrammarModelStatus.error;
      _grammarLoadError = _grammarService.loadError;
    }
    notifyListeners();
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
    final landmarks = _handLandmarkService.processImage(image);

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

    _currentLandmarks = HandLandmarks.fromList(landmarks);

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

    final result = await _grammarService.correctGrammar(phrase);

    if (requestId != _generationRequestId) return;

    _generationResult = result;
    _isGeneratingSentence = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _handLandmarkService.dispose();
    _signClassifier.dispose();
    _grammarService.dispose();
    unawaited(_ttsService.stop());
    super.dispose();
  }
}
