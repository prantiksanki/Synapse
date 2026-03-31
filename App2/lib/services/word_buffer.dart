import '../config/app_config.dart';
import '../models/gesture_result.dart';
import '../models/word_buffer_state.dart';

/// Accumulates gesture tokens and commits them as a phrase when the user
/// pauses (no new unique gesture for [AppConfig.wordBoundary]).
///
/// Key rules:
///   • A token is only added if it differs from the last accepted token,
///     OR the duplicate-suppression window (600 ms) has elapsed.
///   • A phrase is committed (returned) when:
///       – the hand disappears for [wordBoundary], OR
///       – the user holds the SAME gesture for [wordBoundary] with no new input.
///   • Empty phrases are never returned.
class WordBufferService {
  final List<String> _activeTokens = <String>[];
  String _lastCommittedPhrase = '';
  String? _lastStableLabel;
  DateTime? _lastAcceptedAt;

  // Tracks the last time a NEW (non-duplicate) token was added.
  // Boundary fires when now - _lastNewTokenAt >= wordBoundary.
  DateTime? _lastNewTokenAt;

  WordBufferState get state => WordBufferState(
        activeTokens: List<String>.unmodifiable(_activeTokens),
        lastCommittedPhrase: _lastCommittedPhrase,
        lastStableLabel: _lastStableLabel,
        isBoundaryReady: _isBoundaryReady(DateTime.now()),
      );

  /// Feed the latest gesture into the buffer.
  ///
  /// Returns the committed phrase string when a word boundary is detected,
  /// or null if still accumulating.
  String? ingest(GestureResult? gestureResult) {
    final now = DateTime.now();

    if (gestureResult != null &&
        gestureResult.confidence >= AppConfig.gestureConfidenceThreshold) {

      final isDuplicate = _lastStableLabel == gestureResult.label &&
          _lastAcceptedAt != null &&
          now.difference(_lastAcceptedAt!) < AppConfig.duplicateSuppression;

      if (!isDuplicate) {
        // New unique token — add to buffer and reset boundary timer.
        _activeTokens.add(gestureResult.label);
        _lastStableLabel = gestureResult.label;
        _lastAcceptedAt = now;
        _lastNewTokenAt = now;  // Reset: user made a new gesture
      }
      // Whether duplicate or not, check if the user has been holding long enough.
      // If no new token has appeared for wordBoundary, commit.
      if (_isBoundaryReady(now)) {
        return _commit();
      }
      return null;
    }

    // No hand (or below threshold) — check boundary.
    if (_isBoundaryReady(now)) {
      return _commit();
    }
    return null;
  }

  /// Force-commit whatever is in the buffer right now (e.g. user taps a button).
  String? forceCommit() {
    if (_activeTokens.isEmpty) return null;
    return _commit();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  bool _isBoundaryReady(DateTime now) {
    if (_activeTokens.isEmpty) return false;
    if (_lastNewTokenAt == null) return false;
    return now.difference(_lastNewTokenAt!) >= AppConfig.noHandSentenceTrigger;
  }

  String _commit() {
    final phrase = _activeTokens.join(' ');
    _lastCommittedPhrase = phrase;
    _activeTokens.clear();
    _lastStableLabel = null;
    _lastAcceptedAt = null;
    _lastNewTokenAt = null;
    return phrase;
  }
}
