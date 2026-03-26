import 'dart:math';
import '../models/classification_result.dart';

/// Sub-mode for the rule-based classifier — mirrors the 4 modes in main.py.
enum RuleSubMode { all, alphabet, numbers, words }

/// Pure-Dart port of the ISL rule-based classifier from
/// sign-language-recognition/main.py.
///
/// Input : raw 21-point landmark list as returned by HandLandmarkService
///         (each element is [x, y] or [x, y, z], values normalised 0–1).
/// Output: [ClassificationResult] with confidence = 1.0, or null when no
///         gesture matched in the selected sub-mode.
class RuleClassifier {
  // ─── Landmark indices (same as main.py) ────────────────────────────────────
  static const int _wrist = 0;
  static const int _thumbMcp = 2, _thumbTip = 4;
  static const int _indexMcp = 5, _indexPip = 6, _indexDip = 7, _indexTip = 8;
  static const int _middleMcp = 9, _middlePip = 10, _middleTip = 12;
  static const int _ringMcp = 13, _ringPip = 14, _ringTip = 16;
  static const int _pinkyMcp = 17, _pinkyPip = 18, _pinkyTip = 20;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Classify using the given [subMode]. Returns null when nothing matched.
  ClassificationResult? classify(
    List<List<double>> landmarks,
    RuleSubMode subMode,
  ) {
    if (landmarks.length != 21) return null;

    switch (subMode) {
      case RuleSubMode.alphabet:
        final label = _classifyAlphabet(landmarks);
        if (label == null) return null;
        return _result('Letter: $label');

      case RuleSubMode.numbers:
        final label = _classifyNumbers(landmarks);
        if (label == null) return null;
        return _result('Number: $label');

      case RuleSubMode.words:
        final label = _classifyWords(landmarks);
        if (label == null) return null;
        return _result(label);

      case RuleSubMode.all:
        final results = <String>[];
        final word = _classifyWords(landmarks);
        if (word != null) results.add(word);
        final number = _classifyNumbers(landmarks);
        if (number != null) results.add('#$number');
        final letter = _classifyAlphabet(landmarks);
        if (letter != null) results.add('[$letter]');
        if (results.isEmpty) return null;
        return _result(results.join(' | '));
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static ClassificationResult _result(String label) => ClassificationResult(
        label: label,
        labelIndex: 0,
        confidence: 1.0,
        probabilities: {label: 1.0},
      );

  /// Euclidean distance between two landmark points (x, y[, z]).
  static double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    final dz = (a.length > 2 && b.length > 2) ? a[2] - b[2] : 0.0;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Finger extended: tip[1] < pip[1] < mcp[1]  (y grows downward in image space).
  static bool _isFingerExtended(
    List<List<double>> c,
    int tip,
    int pip,
    int mcp,
  ) {
    return c[tip][1] < c[pip][1] && c[pip][1] < c[mcp][1];
  }

  /// Thumb extended: tip is further from index MCP than thumb MCP is.
  static bool _isThumbExtended(List<List<double>> c) {
    return (c[_thumbTip][0] - c[_indexMcp][0]).abs() >
        (c[_thumbMcp][0] - c[_indexMcp][0]).abs();
  }

  static _FingerStates _fingerStates(List<List<double>> c) => _FingerStates(
        thumb: _isThumbExtended(c),
        index: _isFingerExtended(c, _indexTip, _indexPip, _indexMcp),
        middle: _isFingerExtended(c, _middleTip, _middlePip, _middleMcp),
        ring: _isFingerExtended(c, _ringTip, _ringPip, _ringMcp),
        pinky: _isFingerExtended(c, _pinkyTip, _pinkyPip, _pinkyMcp),
      );

  static bool _touching(
    List<List<double>> c,
    int tip1,
    int tip2, {
    double threshold = 0.05,
  }) =>
      _dist(c[tip1], c[tip2]) < threshold;

  static bool _thumbIndexTouching(List<List<double>> c,
          {double threshold = 0.05}) =>
      _touching(c, _thumbTip, _indexTip, threshold: threshold);

  static bool _isFist(List<List<double>> c) {
    final s = _fingerStates(c);
    return !s.index && !s.middle && !s.ring && !s.pinky && !s.thumb;
  }

  // ─── Numbers 0–9 ───────────────────────────────────────────────────────────

  String? _classifyNumbers(List<List<double>> c) {
    final s = _fingerStates(c);

    if (_isFist(c) && !s.thumb) return '0';
    if (s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) return '1';
    if (s.index && s.middle && !s.ring && !s.pinky && !s.thumb) return '2';
    if (s.thumb && s.index && s.middle && !s.ring && !s.pinky) return '3';
    if (s.index && s.middle && s.ring && s.pinky && !s.thumb) return '4';
    if (s.index && s.middle && s.ring && s.pinky && s.thumb) return '5';
    if (s.thumb && s.pinky && !s.index && !s.middle && !s.ring) return '6';
    if (s.thumb && s.index && s.middle && !s.ring && s.pinky) return '7';
    if (s.thumb && s.index && s.middle && s.ring && !s.pinky) return '8';
    if (_thumbIndexTouching(c, threshold: 0.06) && s.middle && s.ring && s.pinky) {
      return '9';
    }
    return null;
  }

  // ─── Alphabet A–Z ──────────────────────────────────────────────────────────

  String? _classifyAlphabet(List<List<double>> c) {
    final s = _fingerStates(c);

    // A — fist with thumb to the side
    if (!s.index && !s.middle && !s.ring && !s.pinky) {
      if (s.thumb && c[_thumbTip][0] < c[_indexMcp][0]) return 'A';
    }

    // B — four fingers extended, thumb folded
    if (s.index && s.middle && s.ring && s.pinky && !s.thumb) return 'B';

    // C — curved hand, moderate gap between thumb and index tips
    if (!s.index && !s.middle && !s.ring && !s.pinky) {
      final d = _dist(c[_indexTip], c[_thumbTip]);
      if (d > 0.08 && d < 0.18) return 'C';
    }

    // D — index up, thumb touches middle tip
    if (s.index && !s.middle && !s.ring && !s.pinky) {
      if (_dist(c[_thumbTip], c[_middleTip]) < 0.07) return 'D';
    }

    // E — all fingers bent, nothing extended
    if (!s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) return 'E';

    // F — index + thumb circle, others extended
    if (_thumbIndexTouching(c, threshold: 0.06) && s.middle && s.ring && s.pinky) {
      return 'F';
    }

    // G — index pointing sideways (tip near wrist height)
    if (s.index && !s.middle && !s.ring && !s.pinky) {
      if ((c[_indexTip][1] - c[_wrist][1]).abs() < 0.12) return 'G';
    }

    // H — index+middle pointing sideways
    if (s.index && s.middle && !s.ring && !s.pinky) {
      if ((c[_indexTip][1] - c[_wrist][1]).abs() < 0.12) return 'H';
    }

    // I — only pinky extended
    if (s.pinky && !s.index && !s.middle && !s.ring && !s.thumb) return 'I';

    // J — pinky + thumb
    if (s.pinky && !s.index && !s.middle && !s.ring && s.thumb) return 'J';

    // K — index+middle up, thumb near middle PIP
    if (s.index && s.middle && !s.ring && !s.pinky) {
      if ((c[_thumbTip][1] - c[_middlePip][1]).abs() < 0.05) return 'K';
    }

    // L — index+thumb L-shape (spread apart horizontally)
    if (s.index && s.thumb && !s.middle && !s.ring && !s.pinky) {
      if ((c[_indexTip][0] - c[_thumbTip][0]).abs() > 0.08) return 'L';
    }

    // M — fist, thumb near pinky side
    if (!s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) {
      if (c[_thumbTip][0] > c[_pinkyMcp][0]) return 'M';
    }

    // N — fist, thumb between middle and ring MCP
    if (!s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) {
      final tx = c[_thumbTip][0];
      if (c[_middleMcp][0] < tx && tx < c[_ringMcp][0]) return 'N';
    }

    // O — tight circle between index and thumb tips
    if (!s.index && !s.middle && !s.ring && !s.pinky) {
      final d = _dist(c[_indexTip], c[_thumbTip]);
      if (d > 0.02 && d < 0.07) return 'O';
    }

    // P — index+middle pointing downward
    if (s.index && s.middle && !s.ring && !s.pinky) {
      if (c[_indexTip][1] > c[_wrist][1]) return 'P';
    }

    // Q — index+thumb pointing down
    if (s.index && s.thumb && !s.middle && !s.ring && !s.pinky) {
      if (c[_indexTip][1] > c[_wrist][1]) return 'Q';
    }

    // R — index+middle crossed (very close tips)
    if (s.index && s.middle && !s.ring && !s.pinky) {
      if (_dist(c[_indexTip], c[_middleTip]) < 0.025) return 'R';
    }

    // S — fist, thumb over fingers (tip above index PIP)
    if (!s.index && !s.middle && !s.ring && !s.pinky) {
      if (s.thumb && c[_thumbTip][1] < c[_indexPip][1]) return 'S';
    }

    // T — fist, thumb between index and middle MCP
    if (!s.index && !s.middle && !s.ring && !s.pinky) {
      final tx = c[_thumbTip][0];
      if (c[_indexMcp][0] < tx && tx < c[_middleMcp][0]) return 'T';
    }

    // U — index+middle together pointing up (tips close)
    if (s.index && s.middle && !s.ring && !s.pinky && !s.thumb) {
      if (_dist(c[_indexTip], c[_middleTip]) < 0.04) return 'U';
    }

    // V — index+middle spread (peace sign)
    if (s.index && s.middle && !s.ring && !s.pinky && !s.thumb) {
      if (_dist(c[_indexTip], c[_middleTip]) > 0.05) return 'V';
    }

    // W — index+middle+ring extended
    if (s.index && s.middle && s.ring && !s.pinky && !s.thumb) return 'W';

    // X — index finger hooked (tip below DIP, DIP above PIP — bent)
    if (!s.middle && !s.ring && !s.pinky) {
      if (c[_indexTip][1] > c[_indexDip][1] &&
          c[_indexDip][1] < c[_indexPip][1]) {
        return 'X';
      }
    }

    // Y — thumb + pinky (shaka)
    if (s.thumb && s.pinky && !s.index && !s.middle && !s.ring) return 'Y';

    // Z — only index extended (traces Z in air)
    if (s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) return 'Z';

    return null;
  }

  // ─── Common words / gestures ───────────────────────────────────────────────

  String? _classifyWords(List<List<double>> c) {
    final s = _fingerStates(c);
    final thumbTip = c[_thumbTip];
    final wrist = c[_wrist];
    final middleTip = c[_middleTip];

    // Good / Thumbs Up — thumb only, tip well above wrist
    if (s.thumb && !s.index && !s.middle && !s.ring && !s.pinky) {
      if (thumbTip[1] < wrist[1] - 0.08) return 'Good (Thumbs Up)';
    }

    // Bad / Thumbs Down — thumb only, tip below wrist
    if (s.thumb && !s.index && !s.middle && !s.ring && !s.pinky) {
      if (thumbTip[1] > wrist[1] + 0.05) return 'Bad (Thumbs Down)';
    }

    // Hello / Namaste — open palm up
    if (s.index && s.middle && s.ring && s.pinky && s.thumb) {
      if (middleTip[1] < wrist[1]) return 'Hello / Namaste';
    }

    // Stop / Wait — four fingers up, thumb folded
    if (s.index && s.middle && s.ring && s.pinky && !s.thumb) {
      if (middleTip[1] < wrist[1]) return 'Stop / Wait';
    }

    // OK — thumb+index circle
    if (_thumbIndexTouching(c, threshold: 0.06) && s.middle && s.ring && s.pinky) {
      return 'OK';
    }

    // I Love You (ILY)
    if (s.thumb && s.index && s.pinky && !s.middle && !s.ring) return 'I Love You';

    // Call Me / Phone
    if (s.thumb && s.pinky && !s.index && !s.middle && !s.ring) return 'Call Me';

    // Peace / Victory — index+middle spread
    if (s.index && s.middle && !s.ring && !s.pinky) {
      if (_dist(c[_indexTip], c[_middleTip]) > 0.05) return 'Peace / Victory';
    }

    // Pointing — only index
    if (s.index && !s.middle && !s.ring && !s.pinky && !s.thumb) return 'Pointing';

    // Fist / Yes
    if (_isFist(c)) return 'Fist (Yes)';

    // Rock On
    if (s.index && s.pinky && !s.middle && !s.ring && !s.thumb) return 'Rock On';

    // Three
    if (s.thumb && s.index && s.middle && !s.ring && !s.pinky) return 'Three';

    return null;
  }
}

// ─── Internal helper ──────────────────────────────────────────────────────────

class _FingerStates {
  final bool thumb, index, middle, ring, pinky;
  const _FingerStates({
    required this.thumb,
    required this.index,
    required this.middle,
    required this.ring,
    required this.pinky,
  });
}
