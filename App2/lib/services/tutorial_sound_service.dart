import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays correct / incorrect feedback from prepacked asset files.
///
/// NOTE: the old algorithm generated in-memory WAV tones, which caused
/// repeated audio focus changes in call mode. We now play the provided
/// asset clips directly and avoid auto tone generation.
class TutorialSoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;

  TutorialSoundService();

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> playCorrect() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/correct.mpeg'));
    } catch (_) {
      // silent fail, no fallback tone generation
    }
  }

  Future<void> playIncorrect() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/incorrect.mpeg'));
    } catch (_) {
      // silent fail, no fallback tone generation
    }
  }

  Future<void> _playAssetFallback(String asset) async {
    // no-op now; we directly play assets and avoid waveform generation.
  }

  void dispose() => _player.dispose();
}

