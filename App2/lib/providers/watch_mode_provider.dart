import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../services/sign_image_service.dart';
import '../services/speech_service.dart';

enum WatchModeState {
  idle,
  loading,
  playing,
  listening,
  paused,
  permissionDenied,
  error,
}

/// Orchestrates Watch section: plays Video.mp4 in a loop while continuously
/// listening to the microphone and converting speech → sign-language images.
class WatchModeProvider extends ChangeNotifier {
  final SpeechService _speechService = SpeechService();
  final SignImageService _signImageService = SignImageService();

  VideoPlayerController? _videoController;
  Timer? _restartTimer;
  bool _restartPending = false; // prevents double-restart from isFinal + onStopped

  WatchModeState _state = WatchModeState.idle;
  String _statusMessage = '';
  String _rawTranscript = '';
  List<SignImageSegment> _segments = [];
  bool _initialized = false;

  WatchModeState get state => _state;
  String get statusMessage => _statusMessage;
  String get rawTranscript => _rawTranscript;
  List<SignImageSegment> get segments => _segments;
  VideoPlayerController? get videoController => _videoController;
  bool get isPlaying => _state == WatchModeState.playing;

  // ── Initialization ──────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _setState(WatchModeState.loading, 'Loading...');

    await _signImageService.initialize();

    _videoController = VideoPlayerController.asset('assets/Video.mp4');
    try {
      await _videoController!.initialize();
      _videoController!.setLooping(true);
    } catch (e) {
      debugPrint('[WatchMode] Video init error: $e');
      _setState(WatchModeState.error, 'Failed to load video.');
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setState(WatchModeState.permissionDenied, 'Microphone Permission Required');
      return;
    }

    final sttAvailable = await _speechService.initialize();
    if (!sttAvailable) {
      _setState(WatchModeState.error, 'Speech recognition unavailable on this device.');
      return;
    }

    _speechService.onResult = _onSpeechResult;
    _speechService.onStopped = _onSpeechStopped;

    await startPlaying();
  }

  // ── Playback control ────────────────────────────────────────────────────────

  Future<void> startPlaying() async {
    if (_state == WatchModeState.playing) return;
    _restartTimer?.cancel();
    _restartPending = false;
    await _videoController?.play();
    _segments = [];
    _rawTranscript = '';
    _setState(WatchModeState.playing, 'Ready - starting speech listen');
    await _startSTT();
  }

  Future<void> pausePlaying() async {
    if (_state != WatchModeState.playing) return;
    _restartTimer?.cancel();
    _restartPending = false;
    await _videoController?.pause();
    await _speechService.stopListening();
    _setState(WatchModeState.paused, 'Paused');
  }

  Future<void> stopPlaying() async {
    _restartTimer?.cancel();
    _restartPending = false;
    await _speechService.stopListening();
    await _videoController?.pause();
    _segments = [];
    _rawTranscript = '';
    _setState(WatchModeState.idle, '');
  }

  // ── STT lifecycle ───────────────────────────────────────────────────────────

  /// Starts STT. Cancels first to ensure the engine is fully stopped,
  /// then waits 300 ms for Android to release its audio session.
  Future<void> _startSTT() async {
    await _speechService.cancelListening();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_state != WatchModeState.playing) return;
    await _speechService.startListeningSilent();
    _setState(WatchModeState.listening, 'Listening...');
    debugPrint('[WatchMode] STT started');
  }

  void _scheduleRestart() {
    if (_restartPending) return; // already scheduled
    _restartPending = true;
    _restartTimer?.cancel();
    // 600 ms gap lets Android fully close the previous session before opening new one.
    _restartTimer = Timer(const Duration(milliseconds: 600), () {
      _restartPending = false;
      if (_state == WatchModeState.playing) {
        _setState(WatchModeState.listening, 'Listening...');
        _startSTT();
      }
    });
  }

  // ── STT callbacks ───────────────────────────────────────────────────────────

  void _onSpeechResult(String text, bool isFinal) {
    _rawTranscript = text;

    if (isFinal) {
      // Utterance complete — generate segments now and show them.
      _setState(WatchModeState.playing, 'Converting to Sign Language...');
      _segments = _signImageService.textToSegments(text);
      // Engine is about to stop — schedule restart.
      // _onSpeechStopped will also fire; _restartPending prevents double-scheduling.
      if (_state == WatchModeState.playing) _scheduleRestart();
    } else {
      // Partial result — update transcript display only, no segment churn.
      _setState(WatchModeState.listening, 'Listening...');
    }
  }

  void _onSpeechStopped() {
    if (_state != WatchModeState.playing) return;
    _scheduleRestart();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setState(WatchModeState s, String message) {
    _state = s;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _speechService.dispose();
    _signImageService.dispose();
    _videoController?.dispose();
    super.dispose();
  }
}
