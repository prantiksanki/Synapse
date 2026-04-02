import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../services/sign_image_service.dart';
import '../services/speech_service.dart';
import '../services/system_audio_service.dart';
import '../services/t5_grammar_service.dart';
import '../services/t5_model_downloader.dart';

enum WatchModeState {
  idle,
  loading,
  playing,
  listening,
  paused,
  permissionDenied,
  error,
}

enum WatchTranscriptSource { none, systemAudio, microphone }
enum WatchConversionEngine { none, t5Offline, ruleGloss }

/// Watch mode orchestration:
/// 1) Video playback loop
/// 2) Primary transcript source: system audio capture (MediaProjection)
/// 3) Fallback transcript source: microphone STT
/// 4) Offline text -> gloss -> sign sequence mapping (all Dart-side logic)
class WatchModeProvider extends ChangeNotifier {
  final SpeechService _speechService = SpeechService();
  final SystemAudioService _systemAudioService = SystemAudioService();
  final SignImageService _signImageService = SignImageService();
  final T5GrammarService _t5GrammarService = T5GrammarService();
  final T5ModelDownloader _t5Downloader = T5ModelDownloader();

  VideoPlayerController? _videoController;
  Timer? _restartTimer;
  bool _restartPending = false;

  bool _systemProjectionRequested = false;
  bool _usingSystemAudio = false;
  bool _pipelineEnsureInFlight = false;
  bool _systemStartInFlight = false;
  DateTime? _lastSystemStartAttemptAt;
  bool _speechAvailable = false;
  bool _t5Ready = false;
  WatchTranscriptSource _lastSource = WatchTranscriptSource.none;
  WatchConversionEngine _lastEngine = WatchConversionEngine.none;
  String _lastGloss = '';

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
  WatchTranscriptSource get transcriptSource => _lastSource;
  WatchConversionEngine get conversionEngine => _lastEngine;
  String get lastGloss => _lastGloss;

  String get transcriptSourceLabel => switch (_lastSource) {
        WatchTranscriptSource.systemAudio => 'System Audio',
        WatchTranscriptSource.microphone => 'Microphone',
        WatchTranscriptSource.none => 'No Source',
      };

  String get conversionEngineLabel => switch (_lastEngine) {
        WatchConversionEngine.t5Offline => 'T5 Offline',
        WatchConversionEngine.ruleGloss => 'Rule Gloss',
        WatchConversionEngine.none => 'No Engine',
      };

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _setState(WatchModeState.loading, 'Loading Watch mode...');

    await _signImageService.initialize();

    _videoController = VideoPlayerController.asset('assets/Video.mp4');
    try {
      await _videoController!.initialize();
      _videoController!.setLooping(true);
      _videoController!.addListener(_onVideoTick);
    } catch (e) {
      debugPrint('[WatchMode] Video init error: $e');
      _setState(WatchModeState.error, 'Failed to load video.');
      return;
    }

    await _initTranscriptPipelines();
    await _initT5IfAvailable();

    await startPlaying();
  }

  Future<void> _initTranscriptPipelines() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setState(WatchModeState.permissionDenied, 'Microphone Permission Required');
      return;
    }

    _speechAvailable = await _speechService.initialize();
    _speechService.onResult = (text, isFinal) => _onTranscript(text, isFinal, source: 'mic');
    _speechService.onStopped = _onSpeechStopped;

    _systemAudioService.initialize();
    _systemAudioService.onTranscript = (text, isFinal) =>
        _onTranscript(text, isFinal, source: 'system');
    _systemAudioService.onProjectionGranted = () {
      _systemProjectionRequested = true;
      _setState(WatchModeState.listening, 'Starting system audio capture...');
      unawaited(_tryStartSystemCapture());
    };
    _systemAudioService.onProjectionDenied = () {
      _systemProjectionRequested = false;
      _usingSystemAudio = false;
      unawaited(_ensureMicListening());
    };
    _systemAudioService.onStatus = (status) {
      _usingSystemAudio = status == WatchCaptureStatus.capturing;
      if (_usingSystemAudio) {
        _lastSource = WatchTranscriptSource.systemAudio;
        _setState(WatchModeState.listening, 'Listening (system audio)...');
      } else if (_state == WatchModeState.playing || _state == WatchModeState.listening) {
        _ensureMicListening();
      }
    };
    _systemAudioService.onError = (message) {
      debugPrint('[WatchMode] System audio error: $message');
      _usingSystemAudio = false;
      _ensureMicListening();
    };

    if (!_speechAvailable) {
      debugPrint('[WatchMode] Microphone STT unavailable; system audio only mode');
    }
  }

  Future<void> _initT5IfAvailable() async {
    try {
      final downloaded = await _t5Downloader.allModelsDownloaded();
      if (!downloaded) {
        _t5Ready = false;
        return;
      }

      final cfg = await _t5Downloader.readConfig();
      await _t5GrammarService.load(
        encoderPath: await _t5Downloader.encoderPath(),
        decoderPath: await _t5Downloader.decoderPath(),
        vocabPath: await _t5Downloader.vocabPath(),
        hiddenDim: cfg['hidden_dim'] ?? 512,
      );
      _t5Ready = _t5GrammarService.isReady;
      debugPrint('[WatchMode] T5 ready: $_t5Ready');
    } catch (e) {
      debugPrint('[WatchMode] T5 init failed: $e');
      _t5Ready = false;
    }
  }

  Future<void> startPlaying() async {
    if (_state == WatchModeState.playing) return;
    _restartTimer?.cancel();
    _restartPending = false;
    await _videoController?.play();
    _segments = [];
    _rawTranscript = '';
    _setState(WatchModeState.playing, 'Ready - listening for video/audio...');
    await _ensureListeningPipeline();
  }

  Future<void> pausePlaying() async {
    if (_state != WatchModeState.playing && _state != WatchModeState.listening) return;
    _restartTimer?.cancel();
    _restartPending = false;
    await _videoController?.pause();
    await _speechService.stopListening();
    await _systemAudioService.stopCapture();
    _usingSystemAudio = false;
    _setState(WatchModeState.paused, 'Paused');
  }

  Future<void> stopPlaying() async {
    _restartTimer?.cancel();
    _restartPending = false;
    await _speechService.stopListening();
    await _systemAudioService.stopCapture();
    _usingSystemAudio = false;
    await _videoController?.pause();
    _segments = [];
    _rawTranscript = '';
    _setState(WatchModeState.idle, '');
  }

  Future<void> _ensureListeningPipeline() async {
    if (_state != WatchModeState.playing && _state != WatchModeState.listening) return;
    if (_pipelineEnsureInFlight) return;

    _pipelineEnsureInFlight = true;
    try {
      if (AppConfig.watchPreferSystemAudio && !_systemProjectionRequested) {
        _systemProjectionRequested = true;
        try {
          _setState(WatchModeState.listening, 'Requesting system audio access...');
          await _systemAudioService.requestMediaProjectionConsent();
        } catch (e) {
          debugPrint('[WatchMode] Projection request failed: $e');
          _usingSystemAudio = false;
        }
      } else if (AppConfig.watchPreferSystemAudio) {
        await _tryStartSystemCapture();
      }

      if (!_systemAudioService.isCapturing) {
        await _ensureMicListening();
      }
    } finally {
      _pipelineEnsureInFlight = false;
    }
  }

  Future<void> _ensureMicListening() async {
    if (!_speechAvailable) return;
    if (_speechService.isListening) return;
    if (_state != WatchModeState.playing && _state != WatchModeState.listening) return;

    await _speechService.cancelListening();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_state != WatchModeState.playing && _state != WatchModeState.listening) return;

    await _speechService.startListeningSilent();
    _lastSource = WatchTranscriptSource.microphone;
    _setState(WatchModeState.listening, 'Listening (microphone)...');
  }

  Future<void> _tryStartSystemCapture() async {
    if (_systemAudioService.isCapturing) return;
    if (_systemStartInFlight) return;

    final now = DateTime.now();
    if (_lastSystemStartAttemptAt != null &&
        now.difference(_lastSystemStartAttemptAt!) <
            const Duration(milliseconds: 1500)) {
      return;
    }

    _systemStartInFlight = true;
    _lastSystemStartAttemptAt = now;
    try {
      await _systemAudioService.startCapture();
    } catch (_) {
      _usingSystemAudio = false;
    } finally {
      _systemStartInFlight = false;
    }
  }

  void _onSpeechStopped() {
    if (_state != WatchModeState.playing && _state != WatchModeState.listening) return;
    if (_usingSystemAudio) return;
    _scheduleRestart();
  }

  void _scheduleRestart() {
    if (_restartPending) return;
    _restartPending = true;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 400), () async {
      _restartPending = false;
      if (_state == WatchModeState.playing || _state == WatchModeState.listening) {
        await _ensureListeningPipeline();
      }
    });
  }

  void _onVideoTick() {
    final playing = _videoController?.value.isPlaying ?? false;
    if (!playing) return;

    // Requirement: whenever media is playing, keep sign-sequence pipeline active.
    if ((_state == WatchModeState.playing || _state == WatchModeState.listening) &&
        !_usingSystemAudio &&
        !_speechService.isListening &&
        !_pipelineEnsureInFlight) {
      unawaited(_ensureListeningPipeline());
    }
  }

  void _onTranscript(String text, bool isFinal, {required String source}) {
    _rawTranscript = text;

    if (!isFinal) {
      _lastSource = source == 'system'
          ? WatchTranscriptSource.systemAudio
          : WatchTranscriptSource.microphone;
      _setState(WatchModeState.listening,
          source == 'system' ? 'Listening (system audio)...' : 'Listening (microphone)...');
      return;
    }

    _setState(WatchModeState.playing, 'Converting to sign sequence...');
    unawaited(_buildSignSequence(text, source: source));
  }

  Future<void> _buildSignSequence(String text, {required String source}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _lastEngine = WatchConversionEngine.none;
    String normalized = trimmed;
    if (_t5Ready) {
      try {
        final t5Result = await _t5GrammarService.correctGrammar(trimmed);
        final out = t5Result.sentence.trim();
        if (out.isNotEmpty) {
          normalized = out;
          _lastEngine = WatchConversionEngine.t5Offline;
        }
      } catch (e) {
        debugPrint('[WatchMode] T5 normalize failed: $e');
      }
    }
    if (_lastEngine == WatchConversionEngine.none) {
      _lastEngine = WatchConversionEngine.ruleGloss;
    }

    final gloss = _toAslGloss(normalized);
    _lastGloss = gloss;
    _segments = _signImageService.textToSegments(gloss);
    _setState(WatchModeState.playing,
        'Showing sign sequence (${source == 'system' ? 'system audio' : 'mic'})');
  }

  String _toAslGloss(String transcript) {
    String text = transcript.toUpperCase().trim();

    text = text.replaceAll(RegExp(r"[^\w\s-]"), '');
    text = text.replaceAll(RegExp(r'\b(A|AN|THE)\b'), '');
    text = text.replaceAll(
      RegExp(
        r'\b(AM|IS|ARE|WAS|WERE|BE|BEEN|BEING|TO|FOR|IN|ON|AT|BY|WITH|FROM|INTO|UP|DOWN|OUT|OVER|UNDER|BEHIND|ABOVE|BELOW|AGAINST|OFF|AGAIN|WANT)\b',
      ),
      '',
    );

    text = text
        .replaceAll("I'M", 'I')
        .replaceAll("YOU'RE", 'YOU')
        .replaceAll("HE'S", 'HE')
        .replaceAll("SHE'S", 'SHE')
        .replaceAll("IT'S", 'IT')
        .replaceAll("WE'RE", 'WE')
        .replaceAll("THEY'RE", 'THEY')
        .replaceAll("'S", '')
        .replaceAll("'", '');

    const verbConversions = <String, String>{
      'WENT': 'GO',
      'GOING': 'GO',
      'GOES': 'GO',
      'GONE': 'GO',
      'ATE': 'EAT',
      'EATING': 'EAT',
      'EATS': 'EAT',
      'EATEN': 'EAT',
      'SAW': 'SEE',
      'SEEN': 'SEE',
      'SEEING': 'SEE',
      'SEES': 'SEE',
      'DID': 'DO',
      'DOING': 'DO',
      'DOES': 'DO',
      'DONE': 'DO',
      'HAD': 'HAVE',
      'HAS': 'HAVE',
      'HAVING': 'HAVE',
      'CAME': 'COME',
      'COMING': 'COME',
      'COMES': 'COME',
      'BOUGHT': 'BUY',
      'BUYING': 'BUY',
      'BUYS': 'BUY',
      'DONT': 'NO',
    };

    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => verbConversions[w] ?? w)
        .toList();

    final gloss = words.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return gloss;
  }

  void _setState(WatchModeState s, String message) {
    _state = s;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _restartTimer?.cancel();
    _speechService.dispose();
    _systemAudioService.dispose();
    _signImageService.dispose();
    _t5GrammarService.dispose();
    _videoController?.dispose();
    super.dispose();
  }
}
