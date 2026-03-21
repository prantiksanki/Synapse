// word_buffer.dart — Accumulates detected sign letters into words and sentences.
//
// Logic:
//   • Duplicate suppression: the same letter cannot be re-added within 600 ms.
//   • Word boundary: if no letter is added for 1500 ms the current letter
//     sequence is "committed" as a completed word (e.g. H+E+L+P → "HELP").
//   • DELETE gesture removes the last letter from the current word.
//   • SPACE gesture explicitly commits the current word.
//   • Callbacks fire on every state change so the UI can update reactively.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

// -------------------------------------------------------------------------
// Data model for a single buffered letter event
// -------------------------------------------------------------------------

class _LetterEvent {
  final String letter;
  final double confidence;
  final DateTime timestamp;

  const _LetterEvent({
    required this.letter,
    required this.confidence,
    required this.timestamp,
  });
}

// -------------------------------------------------------------------------
// WordBuffer
// -------------------------------------------------------------------------

/// Converts a stream of detected sign letters into complete words.
///
/// Usage:
/// ```dart
/// final buffer = WordBuffer()
///   ..onLetterAdded    = (l) => print('Letter: $l')
///   ..onWordCompleted  = (w) => print('Word: $w')
///   ..onBufferChanged  = ()  => setState(() {});
///
/// buffer.addLetter('H', 0.92);
/// buffer.addLetter('E', 0.88);
/// buffer.addLetter('L', 0.95);
/// buffer.addLetter('P', 0.91);
/// // After 1500 ms of silence → onWordCompleted('HELP')
/// ```
class WordBuffer extends ChangeNotifier {
  // -------------------------------------------------------------------------
  // Timing configuration
  // -------------------------------------------------------------------------

  /// Minimum interval between two registrations of the same letter.
  static const Duration _duplicateCooldown = Duration(milliseconds: 600);

  /// Idle time after which the current letter sequence becomes a complete word.
  static const Duration _wordBoundaryTimeout = Duration(milliseconds: 1500);

  // -------------------------------------------------------------------------
  // Callbacks
  // -------------------------------------------------------------------------

  /// Called each time a letter is successfully added to the current word.
  ValueChanged<String>? onLetterAdded;

  /// Called when the current word is committed (either by timeout or SPACE).
  ValueChanged<String>? onWordCompleted;

  /// Called whenever any buffer state changes (letter added, word committed, clear).
  VoidCallback? onBufferChanged;

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  /// Letters of the word currently being assembled.
  final List<String> _currentLetters = [];

  /// All words completed so far in this session.
  final List<String> _completedWords = [];

  /// Full history of letter events (for debugging / replay).
  final List<_LetterEvent> _history = [];

  /// Timer that fires to commit the current word after a period of silence.
  Timer? _wordBoundaryTimer;

  /// The last letter that was accepted, used for duplicate suppression.
  String _lastLetter = '';

  /// Timestamp of the last accepted letter.
  DateTime _lastLetterTime = DateTime.fromMillisecondsSinceEpoch(0);

  // -------------------------------------------------------------------------
  // Public accessors
  // -------------------------------------------------------------------------

  /// The word currently being assembled (e.g. "HEL").
  String getCurrentWord() => _currentLetters.join();

  /// All completed words in insertion order.
  List<String> getCompletedWords() => List.unmodifiable(_completedWords);

  /// Combined text: completed words + in-progress word.
  String getFullText() {
    final parts = [..._completedWords];
    final current = getCurrentWord();
    if (current.isNotEmpty) parts.add(current);
    return parts.join(' ');
  }

  /// True when there is any content in the buffer.
  bool get hasContent =>
      _currentLetters.isNotEmpty || _completedWords.isNotEmpty;

  // -------------------------------------------------------------------------
  // Core input method
  // -------------------------------------------------------------------------

  /// Register a detected [letter] with associated [confidence].
  ///
  /// The letter is ignored if:
  ///   • It is the same as the last accepted letter and within the cooldown.
  ///   • Confidence is below [minConfidence].
  void addLetter(String letter, double confidence, {double minConfidence = 0.75}) {
    if (letter.isEmpty) return;
    final normalised = letter.trim().toUpperCase();

    // ---- Confidence gate ----
    if (confidence < minConfidence) return;

    final now = DateTime.now();

    // ---- Duplicate suppression ----
    if (normalised == _lastLetter &&
        now.difference(_lastLetterTime) < _duplicateCooldown) {
      return;
    }

    _lastLetter     = normalised;
    _lastLetterTime = now;

    // ---- Special gestures ----
    if (normalised == 'SPACE') {
      _commitCurrentWord();
      return;
    }

    if (normalised == 'DELETE') {
      _deleteLastLetter();
      return;
    }

    // ---- Add letter to current word ----
    _currentLetters.add(normalised);
    _history.add(_LetterEvent(
      letter:     normalised,
      confidence: confidence,
      timestamp:  now,
    ));

    dev.log(
      'Letter added: $normalised (conf=${(confidence * 100).toStringAsFixed(1)}%) '
      '— current word: "${getCurrentWord()}"',
      name: 'WordBuffer',
    );

    // Reset the word-boundary timer on every new letter
    _resetWordBoundaryTimer();

    onLetterAdded?.call(normalised);
    onBufferChanged?.call();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Word management
  // -------------------------------------------------------------------------

  /// Remove the last letter from the current word (DELETE gesture).
  void _deleteLastLetter() {
    if (_currentLetters.isEmpty) {
      // If the current word is empty, undo the last completed word
      if (_completedWords.isNotEmpty) {
        final restored = _completedWords.removeLast().split('');
        _currentLetters.addAll(restored);
        dev.log('DELETE: restored previous word "${getCurrentWord()}"', name: 'WordBuffer');
      }
    } else {
      final removed = _currentLetters.removeLast();
      dev.log('DELETE: removed "$removed", current word "${getCurrentWord()}"', name: 'WordBuffer');
    }

    _resetWordBoundaryTimer();
    onBufferChanged?.call();
    notifyListeners();
  }

  /// Commit the current sequence of letters as a completed word.
  void _commitCurrentWord() {
    _wordBoundaryTimer?.cancel();
    _wordBoundaryTimer = null;

    final word = getCurrentWord();
    if (word.isEmpty) return;

    _completedWords.add(word);
    _currentLetters.clear();

    dev.log('Word committed: "$word"', name: 'WordBuffer');

    onWordCompleted?.call(word);
    onBufferChanged?.call();
    notifyListeners();
  }

  /// Reset the word-boundary countdown timer.
  void _resetWordBoundaryTimer() {
    _wordBoundaryTimer?.cancel();
    _wordBoundaryTimer = Timer(_wordBoundaryTimeout, () {
      dev.log('Word boundary timeout — committing "${getCurrentWord()}"', name: 'WordBuffer');
      _commitCurrentWord();
    });
  }

  // -------------------------------------------------------------------------
  // Manual controls (called from UI)
  // -------------------------------------------------------------------------

  /// Manually commit the in-progress word immediately.
  void commitWord() => _commitCurrentWord();

  /// Clear all buffer state.
  void clear() {
    _wordBoundaryTimer?.cancel();
    _wordBoundaryTimer = null;
    _currentLetters.clear();
    _completedWords.clear();
    _history.clear();
    _lastLetter     = '';
    _lastLetterTime = DateTime.fromMillisecondsSinceEpoch(0);

    dev.log('WordBuffer cleared.', name: 'WordBuffer');
    onBufferChanged?.call();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _wordBoundaryTimer?.cancel();
    super.dispose();
  }
}
