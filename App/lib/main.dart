// main.dart — Entry point for the SYNAPSE sign-language → LLM application.
//
// Architecture overview:
//   CameraService  →  MediaPipeService  →  GestureClassifier
//        ↓                                        ↓
//   (raw frames)                          (letter + confidence)
//                                                 ↓
//                                           WordBuffer
//                                                 ↓
//                                           LlmService
//                                                 ↓
//                                          UI (CameraScreen)
//
// State is managed by AppState (ChangeNotifier) via the Provider package.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'model_downloader.dart';
import 'ui/camera_screen.dart';
import 'ui/download_screen.dart';

// ---------------------------------------------------------------------------
// Application entry point
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const SynapseApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class SynapseApp extends StatelessWidget {
  const SynapseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SYNAPSE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Deep near-black background
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),   // Purple accent
          secondary: const Color(0xFF03DAC6), // Teal accent
          surface: const Color(0xFF1E1E2E),
          background: const Color(0xFF0A0A0A),
          error: const Color(0xFFCF6679),
        ),
        // Card styling
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2E),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        // Elevated button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const _StartupRouter(),
    );
  }
}

// ---------------------------------------------------------------------------
// Startup router — checks if LLM model exists before navigating
// ---------------------------------------------------------------------------

class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  bool _checking = true;
  bool _modelExists = false;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final downloader = ModelDownloader();
    final exists = await downloader.modelExists();
    if (mounted) {
      setState(() {
        _modelExists = exists;
        _checking = false;
      });
      // Update global state
      context.read<AppState>().setModelLoaded(exists);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      // Show splash while checking for model on disk
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SYNAPSE',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6C63FF),
                  letterSpacing: 8,
                ),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ],
          ),
        ),
      );
    }

    // Route based on whether the LLM model is already present
    return _modelExists ? const CameraScreen() : const DownloadScreen();
  }
}

// ---------------------------------------------------------------------------
// AppState — Global state managed via Provider
// ---------------------------------------------------------------------------

/// Holds all shared UI state for the SYNAPSE pipeline.
class AppState extends ChangeNotifier {
  // -- Detection results -----------------------------------------------------

  /// The most recently detected sign label (e.g. "H", "Open", "Thank you")
  String _detectedWord = '';
  String get detectedWord => _detectedWord;

  /// Confidence score [0.0 – 1.0] of the current detection
  double _confidence = 0.0;
  double get confidence => _confidence;

  // -- Buffer state ----------------------------------------------------------

  /// Current in-progress word being built letter by letter (e.g. "HEL")
  String _currentWord = '';
  String get currentWord => _currentWord;

  /// List of fully completed words waiting to be sent to the LLM
  List<String> _completedWords = [];
  List<String> get completedWords => List.unmodifiable(_completedWords);

  // -- LLM output ------------------------------------------------------------

  /// The most recent sentence generated by TinyLlama
  String _generatedSentence = '';
  String get generatedSentence => _generatedSentence;

  // -- Processing flags ------------------------------------------------------

  /// True while the LLM is running inference
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  /// True once the LLM model has been loaded into memory
  bool _isModelLoaded = false;
  bool get isModelLoaded => _isModelLoaded;

  // -- FPS counter -----------------------------------------------------------
  int _fps = 0;
  int get fps => _fps;

  // -------------------------------------------------------------------------
  // Mutators
  // -------------------------------------------------------------------------

  void updateDetection(String word, double conf) {
    _detectedWord = word;
    _confidence = conf;
    notifyListeners();
  }

  void updateCurrentWord(String word) {
    _currentWord = word;
    notifyListeners();
  }

  void addCompletedWord(String word) {
    _completedWords = [..._completedWords, word];
    notifyListeners();
  }

  void setGeneratedSentence(String sentence) {
    _generatedSentence = sentence;
    _isProcessing = false;
    notifyListeners();
  }

  void setProcessing(bool v) {
    _isProcessing = v;
    notifyListeners();
  }

  void setModelLoaded(bool v) {
    _isModelLoaded = v;
    notifyListeners();
  }

  void updateFps(int fps) {
    _fps = fps;
    notifyListeners();
  }

  void clearBuffer() {
    _currentWord = '';
    _completedWords = [];
    _detectedWord = '';
    _confidence = 0.0;
    _generatedSentence = '';
    _isProcessing = false;
    notifyListeners();
  }
}
