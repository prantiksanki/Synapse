// camera_screen.dart — Main screen of SYNAPSE.
//
// Layout (bottom-up stack):
//   1. Full-screen camera preview
//   2. Semi-transparent top bar: "SYNAPSE" title + FPS counter
//   3. Bottom panel:
//      - In-progress word display (H-E-L-P style)
//      - Detected sign label + confidence bar
//      - Generated sentence card
//      - Action buttons (Clear / Generate / Speak)

import 'dart:async';
import 'dart:developer' as dev;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../camera_service.dart';
import '../gesture_classifier.dart';
import '../llm_service.dart';
import '../main.dart';
import '../mediapipe_service.dart';
import '../model_downloader.dart';
import '../word_buffer.dart';
import 'result_widget.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // -------------------------------------------------------------------------
  // Services
  // -------------------------------------------------------------------------
  final _cameraService     = CameraService();
  final _mediaPipeService  = MediaPipeService();
  final _gestureClassifier = GestureClassifier();
  final _wordBuffer        = WordBuffer();
  final _llmService        = LlmService();
  final _tts               = FlutterTts();

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------
  bool _initializing = true;
  bool _cameraReady  = false;
  String? _errorMessage;
  bool _inferring = false; // Guard: one inference at a time

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _initServices();
    _wireWordBuffer();
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.storage].request();
  }

  Future<void> _initServices() async {
    // Load gesture classifier
    try {
      await _gestureClassifier.load();
    } catch (e) {
      dev.log('GestureClassifier init error: $e', name: 'CameraScreen');
    }

    // Load LLM if the model file is present
    try {
      final downloader = ModelDownloader();
      if (await downloader.modelExists()) {
        final path = await downloader.getModelPath();
        final ok = await _llmService.loadModel(path);
        if (mounted) {
          context.read<AppState>().setModelLoaded(ok);
        }
      }
    } catch (e) {
      dev.log('LLM init error: $e', name: 'CameraScreen');
    }

    // Initialize TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    // Initialize camera
    try {
      await _cameraService.initialize();
      _cameraService.onFpsUpdated = (fps) {
        if (mounted) context.read<AppState>().updateFps(fps);
      };
      await _cameraService.startStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      dev.log('Camera init error: $e', name: 'CameraScreen');
      if (mounted) setState(() => _errorMessage = 'Camera error: $e');
    }
  }

  void _wireWordBuffer() {
    _wordBuffer.onLetterAdded = (letter) {
      if (mounted) {
        context.read<AppState>().updateCurrentWord(_wordBuffer.getCurrentWord());
      }
    };

    _wordBuffer.onWordCompleted = (word) {
      if (mounted) {
        context.read<AppState>().addCompletedWord(word);
        context.read<AppState>().updateCurrentWord('');
      }
    };

    _wordBuffer.onBufferChanged = () {
      if (mounted) {
        context.read<AppState>().updateCurrentWord(_wordBuffer.getCurrentWord());
      }
    };
  }

  // -------------------------------------------------------------------------
  // Frame processing pipeline
  // -------------------------------------------------------------------------

  Future<void> _onFrame(CameraImage image) async {
    if (_inferring) return;
    _inferring = true;
    try {
      // 1. Detect hand landmarks via MediaPipe
      final landmarks = await _mediaPipeService.detectLandmarks(image);
      if (landmarks.isEmpty) return;

      // 2. Classify gesture from normalised landmarks
      final result = _gestureClassifier.classify(landmarks);
      final label      = result['label']      as String? ?? '';
      final confidence = result['confidence'] as double? ?? 0.0;

      if (label.isEmpty || label == 'unknown') return;

      // 3. Update global detection state
      if (mounted) {
        context.read<AppState>().updateDetection(label, confidence);
      }

      // 4. Feed letter into the word buffer (handles dedup + word boundaries)
      _wordBuffer.addLetter(label, confidence);
    } finally {
      _inferring = false;
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _generateSentence() async {
    final state = context.read<AppState>();
    final words = _wordBuffer.getCompletedWords();
    final current = _wordBuffer.getCurrentWord();

    final allWords = [
      ...words,
      if (current.isNotEmpty) current,
    ];

    if (allWords.isEmpty) return;

    state.setProcessing(true);
    try {
      final sentence = await _llmService.generateSentence(allWords);
      if (mounted) state.setGeneratedSentence(sentence);
    } catch (e) {
      if (mounted) state.setGeneratedSentence(allWords.join(' '));
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _tts.speak(text);
  }

  void _clear() {
    _wordBuffer.clear();
    context.read<AppState>().clearBuffer();
  }

  // -------------------------------------------------------------------------
  // App lifecycle
  // -------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.stopStream();
    } else if (state == AppLifecycleState.resumed && _cameraReady) {
      _cameraService.startStream(_onFrame);
    }
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    await _cameraService.dispose();
    _gestureClassifier.dispose();
    _wordBuffer.dispose();
    await _llmService.release();
    await _tts.stop();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_initializing) return _buildSplash();
    if (_errorMessage != null) return _buildError(_errorMessage!);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          if (_cameraReady && _cameraService.controller != null)
            _buildCameraPreview(),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // ── Bottom panel ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  // ---- Sub-widgets --------------------------------------------------------

  Widget _buildSplash() => const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SYNAPSE',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6C63FF),
                    letterSpacing: 8,
                  )),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
              SizedBox(height: 16),
              Text('Initialising…', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );

  Widget _buildError(String msg) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFCF6679), size: 64),
                const SizedBox(height: 16),
                Text(msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _errorMessage = null;
                    _initializing = true;
                    _init();
                  }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildCameraPreview() {
    final controller = _cameraService.controller!;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize!.height,
            height: controller.value.previewSize!.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Consumer<AppState>(
      builder: (_, state, __) => Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          bottom: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // App title
            const Text(
              'SYNAPSE',
              style: TextStyle(
                color: Color(0xFF6C63FF),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            // FPS + model status
            Row(
              children: [
                if (state.isModelLoaded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green, width: 0.5),
                    ),
                    child: const Text('LLM',
                        style: TextStyle(color: Colors.green, fontSize: 10)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.fps} FPS',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Consumer<AppState>(
      builder: (_, state, __) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black, Color(0xCC000000), Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Current building word ──────────────────────────────────────
            if (state.currentWord.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.currentWord.split('').join('-'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
              ),

            // ── Completed words row ────────────────────────────────────────
            if (state.completedWords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: state.completedWords
                      .map((w) => _WordChip(word: w))
                      .toList(),
                ),
              ),

            // ── Detected sign + confidence ─────────────────────────────────
            if (state.detectedWord.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF6C63FF), width: 0.5),
                      ),
                      child: Text(
                        state.detectedWord,
                        style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ConfidenceBar(confidence: state.confidence),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(state.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // ── Generated sentence ─────────────────────────────────────────
            if (state.generatedSentence.isNotEmpty)
              ResultWidget(
                sentence: state.generatedSentence,
                onSpeak: () => _speak(state.generatedSentence),
              ),

            if (state.isProcessing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Generating…',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // ── Action buttons ─────────────────────────────────────────────
            Row(
              children: [
                // Clear
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Generate
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: state.isProcessing ? null : _generateSentence,
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Generate Sentence'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      disabledBackgroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

/// Pill chip displaying a completed word.
class _WordChip extends StatelessWidget {
  final String word;
  const _WordChip({required this.word});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(word,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      );
}

/// Animated horizontal confidence bar.
class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color get _color {
    if (confidence >= 0.80) return Colors.green;
    if (confidence >= 0.50) return Colors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: confidence.clamp(0.0, 1.0),
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation<Color>(_color),
          minHeight: 6,
        ),
      );
}
