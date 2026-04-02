import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/gesture_result.dart';
import '../models/hand_landmark.dart';
import '../models/llm_generation_result.dart';
import '../models/word_buffer_state.dart';
import '../services/camera_service.dart';
import '../services/gesture_transition_service.dart';
import '../services/hand_landmark_service.dart';
import '../services/hardware_service.dart';
import '../services/openrouter_service.dart';
import '../services/rule_classifier.dart';
import '../services/sign_image_service.dart';
import '../services/speech_service.dart';
import '../services/t5_grammar_service.dart';
import '../services/t5_model_downloader.dart';
import '../services/tflite_classifier.dart';
import '../services/tts_service.dart';
import '../services/word_buffer.dart';
import '../widgets/sign_image_display.dart';

enum DetectionState { uninitialized, initializing, ready, detecting, error }

enum GrammarModelStatus { idle, downloading, loading, ready, error }

enum AppMode { gestureMode, speechMode, callMode, watchMode }

class DetectionProvider extends ChangeNotifier {
  static const String unsupportedPlatformMessage =
      'Real-time sign language detection is currently supported on Android only. '
      'Run this app on an Android device or emulator with camera access.';

  final CameraService _cameraService = CameraService();
  final HandLandmarkService _handLandmarkService = HandLandmarkService();
  final TfliteClassifier _tfliteClassifier = TfliteClassifier();
  final WordBufferService _wordBufferService = WordBufferService();
  final GestureTransitionService _gestureTransitionService =
      GestureTransitionService();
  final T5GrammarService _grammarService = T5GrammarService();
  final T5ModelDownloader _downloader = T5ModelDownloader();
  final TtsService _ttsService = TtsService();
  final SpeechService _speechService = SpeechService();
  final SignImageService _signImageService = SignImageService();
  final OpenRouterService _openRouterService = OpenRouterService();

  DetectionState _state = DetectionState.uninitialized;
  HandLandmarks? _currentLandmarks;
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

  bool _handIsPresent = false;

  // Rule-based classification state
  DateTime? _lastLetterAcceptedAt;
  Timer? _noHandTimer;

  Timer? _sttRestartDebounce;

  String _rawSpeechText = '';
  String _compressedKeywords = '';
  List<SignImageSegment> _signImageSegments = [];
  bool _isProcessingSpeech = false;
  SpeechListenStatus _speechListenStatus = SpeechListenStatus.idle;
  bool _speechServiceReady = false;

  HardwareService? _hardwareService;

  void Function(String sentence)? onSentenceForCall;

  bool _callModeActive = false;
  bool _watchModeActive = false;

  // ── Getters ─────────────────────────────────────────────────────────────────

  DetectionState get state => _state;
  HandLandmarks? get currentLandmarks => _currentLandmarks;
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

  AppMode get appMode {
    if (_callModeActive) return AppMode.callMode;
    if (_watchModeActive) return AppMode.watchMode;
    if (_handIsPresent) return AppMode.gestureMode;
    return AppMode.speechMode;
  }

  bool get watchModeActive => _watchModeActive;
  bool get handIsPresent => _handIsPresent;
  bool get callModeActive => _callModeActive;

  /// PNG bytes for the sign image of the currently detected gesture letter, or null.
  Uint8List? get currentSignImage {
    final label = _currentGesture?.label;
    if (label == null || label.isEmpty) return null;
    return _signImageService.imageForChar(label);
  }

  String get rawSpeechText => _rawSpeechText;
  String get compressedKeywords => _compressedKeywords;
  List<SignImageSegment> get signImageSegments => _signImageSegments;
  bool get isProcessingSpeech => _isProcessingSpeech;
  SpeechListenStatus get speechListenStatus => _speechListenStatus;
  bool get speechServiceReady => _speechServiceReady;

  // ── Initialize ──────────────────────────────────────────────────────────────

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
      await _tfliteClassifier.load();
      if (!_tfliteClassifier.isReady) {
        debugPrint(
          '[DetectionProvider] TFLite classifier failed to load '
          '(${_tfliteClassifier.loadError}), falling back to rule-based.',
        );
      }
      await _signImageService.initialize();
      _speechServiceReady = await _speechService.initialize();
      _speechService.onResult = _onSpeechResult;
      _speechService.onStopped = _onSpeechStopped;

      _state = DetectionState.ready;
      notifyListeners();

      if (_speechServiceReady) _ensureSttRunning();
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
      notifyListeners();
    } catch (e) {
      _state = DetectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _onCameraImage(CameraImage image) {
    final landmarks = _handLandmarkService.processImage(image);

    // FPS counter — update max once per second, never trigger UI rebuild alone
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;
    if (elapsed >= 1000) {
      _fps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    if (landmarks == null || landmarks.length != 21) {
      final hadLandmarks = _currentLandmarks != null || _currentGesture != null;
      _currentLandmarks = null;
      _currentGesture = null;
      _clearPendingGesture();
      _onNoHandDetected();
      _scheduleNoHandTrigger();
      if (hadLandmarks) notifyListeners();
      return;
    }

    // Hand is present — cancel any pending no-hand timer
    _cancelNoHandTimer();
    _handIsPresent = true;
    _currentLandmarks = HandLandmarks.fromList(landmarks);

    // TFLite classifier — single hand goes into left slot (training convention)
    // Falls back to rule-based if TFLite is not loaded yet.
    final classResult = _tfliteClassifier.isReady
        ? _tfliteClassifier.classify(leftLandmarks: landmarks)
        : classify(landmarks, RuleSubMode.alphabet);

    if (classResult != null) {
      final candidate = GestureResult(
        label: classResult.label,
        labelIndex: classResult.labelIndex,
        confidence: classResult.confidence,
        probabilities: classResult.probabilities,
        timestampMs: now.millisecondsSinceEpoch,
      );
      final stableGesture = _tryAcceptStableGesture(
        candidate: candidate,
        now: now,
      );
      if (stableGesture == null) return;

      final isSame = _currentGesture?.label == stableGesture.label;
      final inWindow =
          _lastLetterAcceptedAt != null &&
          now.difference(_lastLetterAcceptedAt!) <
              AppConfig.duplicateSuppression;

      if (!(isSame && inWindow)) {
        // Accept this letter
        _lastLetterAcceptedAt = now;
        _currentGesture = stableGesture;
        final phrase = _wordBufferService.ingest(_currentGesture);
        if (phrase != null) unawaited(_generateSentence(phrase));
        notifyListeners();
      }
    } else {
      _clearPendingGesture();
    }
  }

  // ── No-hand sentence trigger ─────────────────────────────────────────────────

  void _scheduleNoHandTrigger() {
    if (_noHandTimer != null) return; // already armed
    if (_wordBufferService.state.activeTokens.isEmpty) {
      return; // nothing to commit
    }
    _noHandTimer = Timer(AppConfig.noHandSentenceTrigger, () {
      _noHandTimer = null;
      final phrase = _wordBufferService.forceCommit();
      if (phrase != null && phrase.trim().isNotEmpty) {
        unawaited(_generateSentence(phrase));
      }
    });
  }

  void _cancelNoHandTimer() {
    _noHandTimer?.cancel();
    _noHandTimer = null;
  }

  // ── Sentence / TTS ───────────────────────────────────────────────────────────

  Future<void> speakLatestSentence() async {
    if (!_generationResult.hasSentence) return;
    try {
      await _ttsService.speak(_generationResult.sentence);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  Future<void> forceGenerate() async {
    _cancelNoHandTimer();
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

    if (AppConfig.preferCloudSentenceGeneration &&
        !AppConfig.strictOfflineMode) {
      try {
        final result = await _openRouterService
            .formSentence(phrase)
            .timeout(Duration(milliseconds: AppConfig.cloudSentenceMaxWaitMs));
        if (requestId != _generationRequestId) return;

        final cloudText = result.sentence.trim();
        final finalText = cloudText.isNotEmpty
            ? cloudText
            : _quickComposeFromLetters(phrase);

        _generationResult = cloudText.isNotEmpty
            ? result
            : LlmGenerationResult(
                inputTokens: phrase,
                sentence: finalText,
                latencyMs: result.latencyMs,
                source: 'local_fallback',
              );
        _isGeneratingSentence = false;
        notifyListeners();

        if (finalText.isNotEmpty) {
          if (_callModeActive) {
            onSentenceForCall?.call(finalText);
          } else {
            unawaited(_speakImmediately(finalText));
          }
        }
        return;
      } catch (_) {
        // Fall through to instant local fallback for responsiveness.
      }
    }

    // Local fallback path (or primary path when cloud preference is disabled).
    final instantText = _quickComposeFromLetters(phrase);
    _generationResult = LlmGenerationResult(
      inputTokens: phrase,
      sentence: instantText,
      latencyMs: 0,
      source: 'local_instant',
    );
    _isGeneratingSentence = false;
    notifyListeners();

    if (instantText.trim().isNotEmpty) {
      if (_callModeActive) {
        onSentenceForCall?.call(instantText);
      } else {
        unawaited(_speakImmediately(instantText));
      }
    }
  }

  String _quickComposeFromLetters(String rawTokens) {
    final tokens = rawTokens
        .split(' ')
        .map((t) => t.trim().toUpperCase())
        .where((t) => t.isNotEmpty && t != 'DELETE')
        .toList();

    if (tokens.isEmpty) return '';

    final words = <String>[];
    final current = StringBuffer();
    for (final t in tokens) {
      if (t == 'SPACE') {
        if (current.isNotEmpty) {
          words.add(current.toString().toLowerCase());
          current.clear();
        }
      } else {
        current.write(t);
      }
    }
    if (current.isNotEmpty) {
      words.add(current.toString().toLowerCase());
    }

    if (words.isEmpty) return '';
    if (words.length == 1) return words.first;
    return words.join(' ');
  }

  Future<void> _speakImmediately(String text) async {
    try {
      // Prevent long queued utterances; prioritize latest generated result.
      await _ttsService.stop();
      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('TTS immediate error: $e');
    }
  }

  // ── WebRTC camera handoff ───────────────────────────────────────────────────

  Future<void> releaseCameraForWebRtc() async {
    if (_state == DetectionState.detecting) {
      await _cameraService.stopImageStream();
      _state = DetectionState.ready;
    }
    await _cameraService.dispose();
    notifyListeners();
  }

  Future<void> restoreCameraAfterWebRtc() async {
    if (!isPlatformSupported) return;
    try {
      await _cameraService.initialize();
      _state = DetectionState.ready;
      notifyListeners();
      await startDetection();
    } catch (_) {}
  }

  // ── Call mode ────────────────────────────────────────────────────────────────

  void enterCallModeVideoOnly() {
    // Video call: camera is already released to WebRTC — just flag call mode.
    _callModeActive = true;
    unawaited(_speechService.stopListening());
    _speechListenStatus = SpeechListenStatus.idle;
    notifyListeners();
  }

  void enterCallMode() {
    // Audio call: stop the camera image stream so sign detection stops running.
    _callModeActive = true;
    unawaited(_speechService.stopListening());
    _speechListenStatus = SpeechListenStatus.idle;
    _cancelNoHandTimer();
    if (_state == DetectionState.detecting) {
      unawaited(
        _cameraService.stopImageStream().then((_) {
          _state = DetectionState.ready;
          _currentLandmarks = null;
          _currentGesture = null;
          _handIsPresent = false;
          notifyListeners();
        }),
      );
    } else {
      notifyListeners();
    }
  }

  void exitCallMode() {
    _callModeActive = false;
    // Restart camera stream if it was stopped for an audio call.
    if (_state == DetectionState.ready && isPlatformSupported) {
      unawaited(startDetection());
    }
    if (_speechServiceReady) _ensureSttRunning();
    notifyListeners();
  }

  Future<void> processCallerSpeech(String text) => _processSpeechToSigns(text);

  // ── Watch mode ───────────────────────────────────────────────────────────────

  void enterWatchMode() {
    _watchModeActive = true;
    unawaited(_speechService.stopListening());
    _speechListenStatus = SpeechListenStatus.idle;
    notifyListeners();
  }

  void exitWatchMode() {
    _watchModeActive = false;
    if (_speechServiceReady) _ensureSttRunning();
    notifyListeners();
  }

  // ── STT helpers ──────────────────────────────────────────────────────────────

  void _ensureSttRunning({Duration delay = Duration.zero}) {
    if (!_speechServiceReady) return;
    if (_callModeActive) return;
    if (_watchModeActive) return;
    if (_speechService.isListening) return;
    _sttRestartDebounce?.cancel();
    _sttRestartDebounce = Timer(delay, () {
      if (_callModeActive) return;
      if (_watchModeActive) return;
      if (_speechService.isListening) return;
      _speechListenStatus = SpeechListenStatus.listening;
      unawaited(_speechService.startListening());
    });
  }

  void _onNoHandDetected() {
    if (_callModeActive) return;
    if (_handIsPresent) {
      _handIsPresent = false;
      _ensureSttRunning();
    }
  }

  void _onSpeechStopped() {
    _speechListenStatus = SpeechListenStatus.idle;
    notifyListeners();
    _ensureSttRunning(delay: const Duration(seconds: 1));
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

  // ── Pi hardware integration ──────────────────────────────────────────────────

  void attachHardware(HardwareService hw) {
    if (_hardwareService == hw) return;
    _hardwareService?.onFrame = null;
    _hardwareService = hw;
    hw.onFrame = _onPiFrame;
  }

  void _onPiFrame(Uint8List jpeg) {
    if (_state != DetectionState.detecting && _state != DetectionState.ready) {
      return;
    }
    _handLandmarkService.processJpeg(jpeg).then((landmarks) {
      unawaited(_onPiLandmarks(landmarks));
    });
  }

  Future<void> _onPiLandmarks(List<List<double>>? landmarks) async {
    if (landmarks == null || landmarks.length != 21) {
      _currentLandmarks = null;
      _currentGesture = null;
      _clearPendingGesture();
      _onNoHandDetected();
      _scheduleNoHandTrigger();
      notifyListeners();
      return;
    }

    // Cancel any no-hand timer — hand is present
    _cancelNoHandTimer();
    _handIsPresent = true;
    _currentLandmarks = HandLandmarks.fromList(landmarks);

    final now = DateTime.now();
    final classResult = _tfliteClassifier.isReady
        ? _tfliteClassifier.classify(leftLandmarks: landmarks)
        : classify(landmarks, RuleSubMode.alphabet);

    if (classResult != null) {
      final candidate = GestureResult(
        label: classResult.label,
        labelIndex: classResult.labelIndex,
        confidence: classResult.confidence,
        probabilities: classResult.probabilities,
        timestampMs: now.millisecondsSinceEpoch,
      );
      final stableGesture = _tryAcceptStableGesture(
        candidate: candidate,
        now: now,
      );
      if (stableGesture == null) {
        notifyListeners();
        return;
      }

      final isSame = _currentGesture?.label == stableGesture.label;
      final inWindow =
          _lastLetterAcceptedAt != null &&
          now.difference(_lastLetterAcceptedAt!) <
              AppConfig.duplicateSuppression;

      if (!(isSame && inWindow)) {
        _lastLetterAcceptedAt = now;
        _currentGesture = stableGesture;
        final phrase = _wordBufferService.ingest(_currentGesture);
        if (phrase != null) unawaited(_generateSentence(phrase));
      }
    } else {
      _clearPendingGesture();
    }

    notifyListeners();
  }

  void _clearPendingGesture() {
    _gestureTransitionService.reset();
  }

  GestureResult? _tryAcceptStableGesture({
    required GestureResult candidate,
    required DateTime now,
  }) {
    return _gestureTransitionService.acceptStableGesture(
      candidate: candidate,
      currentLabel: _currentGesture?.label,
      now: now,
      lastAcceptedAt: _lastLetterAcceptedAt,
    );
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _noHandTimer?.cancel();
    _sttRestartDebounce?.cancel();
    _hardwareService?.onFrame = null;
    _cameraService.dispose();
    _handLandmarkService.dispose();
    _tfliteClassifier.dispose();
    _grammarService.dispose();
    unawaited(_ttsService.stop());
    unawaited(_speechService.stopListening());
    _speechService.dispose();
    _signImageService.dispose();
    super.dispose();
  }
}
