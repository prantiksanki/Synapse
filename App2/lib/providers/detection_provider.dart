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
import '../services/sign_image_service.dart';
import '../services/speech_service.dart';
import '../services/t5_grammar_service.dart';
import '../services/t5_model_downloader.dart';
import '../services/tts_service.dart';
import '../services/word_buffer.dart';
import '../widgets/sign_image_display.dart';

enum DetectionState { uninitialized, initializing, ready, detecting, error }

enum GrammarModelStatus { idle, downloading, loading, ready, error }

enum AppMode { gestureMode, speechMode }

class DetectionProvider extends ChangeNotifier {
  static const String unsupportedPlatformMessage =
      'Real-time sign language detection is currently supported on Android only. '
      'Run this app on an Android device or emulator with camera access.';

  final CameraService _cameraService = CameraService();
  final HandLandmarkService _handLandmarkService = HandLandmarkService();
  final SignClassifier _signClassifier = SignClassifier();
  final WordBufferService _wordBufferService = WordBufferService();
  final T5GrammarService _grammarService = T5GrammarService();
  final T5ModelDownloader _downloader = T5ModelDownloader();
  final TtsService _ttsService = TtsService();
  final SpeechService _speechService = SpeechService();
  final SignImageService _signImageService = SignImageService();

  DetectionState _state = DetectionState.uninitialized;
  HandLandmarks? _currentLandmarks;
  ClassificationResult? _currentResult;
  GestureResult? _currentGesture;
  String? _errorMessage;

  GrammarModelStatus _grammarStatus = GrammarModelStatus.idle;
  String? _grammarStatusMessage;
  double _downloadProgress = 0;
  String _downloadFileLabel = '';

  LlmGenerationResult _generationResult = const LlmGenerationResult.idle();
  int _generationRequestId = 0;
  bool _isGeneratingSentence = false;

  int _frameCount = 0;
  double _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // --- Speech / sign-image mode ---
  AppMode _appMode = AppMode.gestureMode;
  DateTime? _handAbsenceStart;
  static const Duration _handAbsenceThreshold = Duration(milliseconds: 1500);

  String _rawSpeechText = '';
  String _compressedKeywords = '';
  List<SignImageSegment> _signImageSegments = [];
  bool _isProcessingSpeech = false;
  SpeechListenStatus _speechListenStatus = SpeechListenStatus.idle;
  bool _speechServiceReady = false;

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
  String? get grammarStatusMessage => _grammarStatusMessage;
  double get downloadProgress => _downloadProgress;
  String get downloadFileLabel => _downloadFileLabel;
  bool get isGrammarReady => _grammarStatus == GrammarModelStatus.ready;

  // Speech / sign-image mode getters
  AppMode get appMode => _appMode;
  String get rawSpeechText => _rawSpeechText;
  String get compressedKeywords => _compressedKeywords;
  List<SignImageSegment> get signImageSegments => _signImageSegments;
  bool get isProcessingSpeech => _isProcessingSpeech;
  SpeechListenStatus get speechListenStatus => _speechListenStatus;
  bool get speechServiceReady => _speechServiceReady;

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
      await _signImageService.initialize();
      _speechServiceReady = await _speechService.initialize();
      _speechService.onResult = _onSpeechResult;
      _speechService.onStopped = _onSpeechStopped;

      _state = DetectionState.ready;
      notifyListeners();

      unawaited(_prepareGrammarModel());
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e is UnsupportedError
          ? unsupportedPlatformMessage
          : e.toString();
      notifyListeners();
    }
  }

  Future<void> _prepareGrammarModel() async {
    try {
      final alreadyDownloaded = await _downloader.allModelsDownloaded();

      if (!alreadyDownloaded) {
        _grammarStatus = GrammarModelStatus.downloading;
        _grammarStatusMessage = 'Downloading grammar model...';
        _downloadProgress = 0;
        notifyListeners();

        await _downloader.downloadAll(
          onProgress: (label, received, total) {
            _downloadFileLabel = label;
            _downloadProgress = total > 0 ? received / total : 0;
            _grammarStatusMessage =
                'Downloading $label... '
                '${(received / 1024 / 1024).toStringAsFixed(1)} MB'
                '${total > 0 ? ' / ${(total / 1024 / 1024).toStringAsFixed(1)} MB' : ''}';
            notifyListeners();
          },
        );
      }

      _grammarStatus = GrammarModelStatus.loading;
      _grammarStatusMessage = 'Loading grammar model...';
      notifyListeners();

      final cfg = await _downloader.readConfig();
      _grammarService.dispose();
      await _grammarService.load(
        encoderPath: await _downloader.encoderPath(),
        decoderPath: await _downloader.decoderPath(),
        vocabPath: await _downloader.vocabPath(),
        hiddenDim: cfg['hidden_dim'] ?? 512,
      );

      if (_grammarService.isReady) {
        _grammarStatus = GrammarModelStatus.ready;
        _grammarStatusMessage = 'T5 grammar model ready';
      } else {
        _grammarStatus = GrammarModelStatus.error;
        _grammarStatusMessage =
            _grammarService.loadError ?? 'Failed to load grammar model.';
      }
      notifyListeners();
    } catch (e) {
      _grammarStatus = GrammarModelStatus.error;
      _grammarStatusMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> downloadAndLoadGrammarModel() => _prepareGrammarModel();

  Future<bool> areModelsDownloaded() => _downloader.allModelsDownloaded();

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
      final phrase = _wordBufferService.ingest(null);
      if (phrase != null) unawaited(_generateSentence(phrase));
      _onNoHandDetected();
      notifyListeners();
      return;
    }

    // Hand is present — reset absence timer and return to gesture mode if needed
    _handAbsenceStart = null;
    if (_appMode == AppMode.speechMode) _switchToGestureMode();

    _currentLandmarks = HandLandmarks.fromList(landmarks);

    try {
      final preprocessed =
          LandmarkProcessor.preProcessNormalizedLandmarks(landmarks);
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
        final phrase = _wordBufferService.ingest(_currentGesture);
        if (phrase != null) unawaited(_generateSentence(phrase));
      } else {
        _currentGesture = null;
        final phrase = _wordBufferService.ingest(null);
        if (phrase != null) unawaited(_generateSentence(phrase));
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

  // ---------------------------------------------------------------------------
  // Speech / sign-image mode helpers
  // ---------------------------------------------------------------------------

  void _onNoHandDetected() {
    _handAbsenceStart ??= DateTime.now();
    if (_appMode == AppMode.gestureMode &&
        DateTime.now().difference(_handAbsenceStart!) >=
            _handAbsenceThreshold) {
      _switchToSpeechMode();
    }
  }

  void _switchToSpeechMode() {
    if (_appMode == AppMode.speechMode) return;
    _appMode = AppMode.speechMode;
    _rawSpeechText = '';
    _compressedKeywords = '';
    _signImageSegments = [];
    if (_speechServiceReady) unawaited(_startListeningLoop());
    notifyListeners();
  }

  void _switchToGestureMode() {
    if (_appMode == AppMode.gestureMode) return;
    _appMode = AppMode.gestureMode;
    _handAbsenceStart = null;
    unawaited(_speechService.stopListening());
    _speechListenStatus = SpeechListenStatus.idle;
    notifyListeners();
  }

  Future<void> _startListeningLoop() async {
    if (_appMode != AppMode.speechMode || _speechService.isListening) return;
    _speechListenStatus = SpeechListenStatus.listening;
    notifyListeners();
    await _speechService.startListening();
  }

  void _onSpeechStopped() {
    if (_appMode != AppMode.speechMode) return;
    _speechListenStatus = SpeechListenStatus.idle;
    notifyListeners();
    // Auto-restart after a brief pause to keep listening continuously.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_appMode == AppMode.speechMode) unawaited(_startListeningLoop());
    });
  }

  void _onSpeechResult(String text, bool isFinal) {
    _rawSpeechText = text;
    notifyListeners();
    if (isFinal) unawaited(_processSpeechToSigns(text));
  }

  Future<void> _processSpeechToSigns(String text) async {
    if (text.trim().isEmpty) return;
    _isProcessingSpeech = true;
    _speechListenStatus = SpeechListenStatus.processing;
    notifyListeners();

    String keywords;
    if (_grammarService.isReady) {
      // Use T5 to normalise grammar first, then apply Dart stop-word filter.
      final t5Result = await _grammarService.correctGrammar(text);
      final t5Out = t5Result.sentence.trim();
      final base = t5Out.isNotEmpty ? t5Out : text;
      keywords = _signImageService.extractKeywordsFallback(base);
    } else {
      keywords = _signImageService.extractKeywordsFallback(text);
    }

    _compressedKeywords = keywords;
    _signImageSegments = _signImageService.textToSegments(keywords);
    _isProcessingSpeech = false;
    _speechListenStatus = SpeechListenStatus.listening;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _cameraService.dispose();
    _handLandmarkService.dispose();
    _signClassifier.dispose();
    _grammarService.dispose();
    unawaited(_ttsService.stop());
    unawaited(_speechService.stopListening());
    _speechService.dispose();
    _signImageService.dispose();
    super.dispose();
  }
}
