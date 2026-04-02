import 'dart:math';
import '../models/classification_result.dart';

/// Sub-mode for the rule-based classifier.
enum RuleSubMode { all, alphabet, numbers, words }

/// Pure-Dart ISL rule-based classifier.
///
/// Input : raw 21-point landmark list as returned by HandLandmarkService
///         (each element is [x, y] or [x, y, z], values normalised 0–1).
/// Output: [ClassificationResult] with confidence = 1.0, or null when no
///         gesture matched in the selected sub-mode.

// Landmark indices
const int _wrist = 0;
const int _thumbMcp = 2, _thumbTip = 4;
const int _indexMcp = 5, _indexPip = 6, _indexDip = 7, _indexTip = 8;
const int _middleMcp = 9, _middlePip = 10, _middleTip = 12;
const int _ringMcp = 13, _ringPip = 14, _ringTip = 16;
const int _pinkyMcp = 17, _pinkyPip = 18, _pinkyTip = 20;

// Public API

final List<List<List<double>>> _frameHistory = [];
DateTime _lastClassificationTime = DateTime.now();

ClassificationResult? classify(
  List<List<double>> landmarks,
  RuleSubMode subMode,
) {
  if (landmarks.length != 21) return null;
  _addFrame(landmarks);

  ClassificationResult? result;

  switch (subMode) {
    case RuleSubMode.alphabet:
      final label = _classifyAlphabet(landmarks);
      if (label != null) result = _result(label);
      break;
    case RuleSubMode.numbers:
      final label = _classifyNumbers(landmarks);
      if (label != null) result = _result(label);
      break;
    case RuleSubMode.words:
      final label = _classifyWords(landmarks);
      if (label != null) result = _result(label);
      break;
    case RuleSubMode.all:
      final letter = _classifyAlphabet(landmarks);
      if (letter != null) result = _result(letter);
      final number = _classifyNumbers(landmarks);
      if (number != null && result == null) result = _result(number);
      break;
  }

  if (result != null) {
    _lastClassificationTime = DateTime.now();
    return result;
  }

  // If hand detected but no gesture classified, check timeout
  if (DateTime.now().difference(_lastClassificationTime) > const Duration(seconds: 6)) {
    return _result('Who are you?');
  }

  return null;
}

// Helpers

ClassificationResult _result(String label) => ClassificationResult(
      label: label,
      labelIndex: 0,
      confidence: 1.0,
      probabilities: {label: 1.0},
    );

double _dist(List<double> a, List<double> b) {
  final dx = a[0] - b[0];
  final dy = a[1] - b[1];
  final dz = (a.length > 2 && b.length > 2) ? a[2] - b[2] : 0.0;
  return sqrt(dx * dx + dy * dy + dz * dz);
}

double _distance(List<double> a, List<double> b) {
  return _dist(a, b);
}

double _angle(
  List<double> a,
  List<double> b,
  List<double> c,
) {
  final abx = a[0] - b[0];
  final aby = a[1] - b[1];

  final cbx = c[0] - b[0];
  final cby = c[1] - b[1];

  final dot = abx * cbx + aby * cby;
  final mag1 = sqrt(abx * abx + aby * aby);
  final mag2 = sqrt(cbx * cbx + cby * cby);

  if (mag1 == 0 || mag2 == 0) return 0;

  final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
  return acos(cosTheta) * 180 / pi;
}

bool _isFingerExtendedByAngle(
  List<List<double>> c,
  int mcp,
  int pip,
  int dip,
  int tip,
) {
  final pipAngle = _angle(c[mcp], c[pip], c[dip]);
  final dipAngle = _angle(c[pip], c[dip], c[tip]);

  return pipAngle > 160 && dipAngle > 150;
}

bool _isThumbExtended(List<List<double>> c) {
  final thumbAngle = _angle(c[_wrist], c[_thumbMcp], c[_thumbTip]);
  return thumbAngle > 150;
}

List<bool> _fingerStates(List<List<double>> c) => [
  _isThumbExtended(c),
  _isFingerExtendedByAngle(
    c,
    _indexMcp,
    _indexPip,
    _indexDip,
    _indexTip,
  ),
  _isFingerExtendedByAngle(
    c,
    _middleMcp,
    _middlePip,
    11,
    _middleTip,
  ),
  _isFingerExtendedByAngle(
    c,
    _ringMcp,
    _ringPip,
    15,
    _ringTip,
  ),
  _isFingerExtendedByAngle(
    c,
    _pinkyMcp,
    _pinkyPip,
    19,
    _pinkyTip,
  ),
];

bool _touching(
  List<List<double>> c,
  int tip1,
  int tip2, {
  double threshold = 0.05,
}) =>
    _dist(c[tip1], c[tip2]) < threshold;

bool _thumbIndexTouching(List<List<double>> c,
        {double threshold = 0.05}) =>
    _touching(c, _thumbTip, _indexTip, threshold: threshold);

bool _isRightHand(List<List<double>> c) {
  return c[_thumbTip][0] < c[_pinkyTip][0];
}

void _addFrame(List<List<double>> landmarks) {
  _frameHistory.add(landmarks);
  if (_frameHistory.length > 10) {
    _frameHistory.removeAt(0);
  }
}

bool _detectJMotion() {
  if (_frameHistory.length < 5) return false;

  final start = _frameHistory.first[_pinkyTip];
  final end = _frameHistory.last[_pinkyTip];

  return (end[0] - start[0]).abs() > 0.08 && (end[1] - start[1]) > 0.05;
}

bool _detectZMotion() {
  if (_frameHistory.length < 5) return false;

  final start = _frameHistory.first[_indexTip];
  final end = _frameHistory.last[_indexTip];

  return (end[0] - start[0]).abs() > 0.08;
}

bool _isFist(List<List<double>> c) {
  final s = _fingerStates(c);
  return !s[1] && !s[2] && !s[3] && !s[4] && !s[0];
}

// Numbers 0–9

String? _classifyNumbers(List<List<double>> c) {
  final s = _fingerStates(c);

  if (_isFist(c) && !s[0]) return '0';
  if (s[1] && !s[2] && !s[3] && !s[4] && !s[0]) return '1';
  if (s[1] && s[2] && !s[3] && !s[4] && !s[0]) return '2';
  if (s[0] && s[1] && s[2] && !s[3] && !s[4]) return '3';
  if (s[1] && s[2] && s[3] && s[4] && !s[0]) return '4';
  if (s[1] && s[2] && s[3] && s[4] && s[0]) return '5';
  if (s[0] && s[4] && !s[1] && !s[2] && !s[3]) return '6';
  if (s[0] && s[1] && s[2] && !s[3] && s[4]) return '7';
  if (s[0] && s[1] && s[2] && s[3] && !s[4]) return '8';
  if (_thumbIndexTouching(c, threshold: 0.06) && s[2] && s[3] && s[4]) {
    return '9';
  }
  return null;
}

// Alphabet A–Z

String? _classifyAlphabet(List<List<double>> c) {
  final s = _fingerStates(c);
  final thumbIndexDist = _dist(c[_thumbTip], c[_indexTip]);
  final thumbMiddleDist = _dist(c[_thumbTip], c[_middleTip]);
  final indexMiddleDist = _dist(c[_indexTip], c[_middleTip]);
  final allFingersCurled = !s[1] && !s[2] && !s[3] && !s[4];
  final rightHand = _isRightHand(c);

  bool thumbLeftOfIndex() {
    return rightHand
        ? c[_thumbTip][0] < c[_indexMcp][0]
        : c[_thumbTip][0] > c[_indexMcp][0];
  }

  if (s[1] && s[2] && s[3] && s[4] && !s[0]) return 'B';
  if (s[1] && s[2] && s[3] && !s[4] && !s[0]) return 'W';
  if (s[0] && s[4] && !s[1] && !s[2] && !s[3]) return 'Y';

  if (s[4] && !s[1] && !s[2] && !s[3] && !s[0]) {
    if (c[_pinkyTip][1] < c[_pinkyPip][1] - 0.03) return 'I';
  }

  if (s[4] && !s[1] && !s[2] && !s[3] && s[0]) {
    if (_detectJMotion()) return 'J';
  }

  if (_thumbIndexTouching(c, threshold: 0.06) &&
      s[2] && s[3] && s[4]) {
    return 'F';
  }

  if (s[1] && !s[2] && !s[3] && !s[4]) {
    final dx = (c[_indexTip][0] - c[_indexMcp][0]).abs();
    final dy = (c[_indexTip][1] - c[_indexMcp][1]).abs();
    if (dx > dy * 1.5) return 'G';
  }

  if (s[1] && s[2] && !s[3] && !s[4]) {
    final idxDx = (c[_indexTip][0] - c[_indexMcp][0]).abs();
    final idxDy = (c[_indexTip][1] - c[_indexMcp][1]).abs();
    if (idxDx > idxDy * 1.5) return 'H';
  }

  if (s[1] && s[2] && !s[3] && !s[4]) {
    if ((c[_thumbTip][1] - c[_middlePip][1]).abs() < 0.05) return 'K';
  }

  if (s[1] && s[0] && !s[2] && !s[3] && !s[4]) {
    if ((c[_indexTip][0] - c[_thumbTip][0]).abs() > 0.08) return 'L';
  }

  if (s[1] && !s[2] && !s[3] && !s[4]) {
    if (thumbMiddleDist < 0.07) return 'D';
  }

  if (s[1] && s[2] && !s[3] && !s[4]) {
    if (c[_indexTip][1] > c[_wrist][1]) return 'P';
  }

  if (s[1] && s[0] && !s[2] && !s[3] && !s[4]) {
    if (c[_indexTip][1] > c[_wrist][1]) return 'Q';
  }

  if (s[1] && s[2] && !s[3] && !s[4]) {
    if (indexMiddleDist < 0.025) return 'R';
  }

  if (s[1] && s[2] && !s[3] && !s[4] && !s[0]) {
    if (indexMiddleDist < 0.04) return 'U';
  }

  if (s[1] && s[2] && !s[3] && !s[4] && !s[0]) {
    if (indexMiddleDist > 0.05) return 'V';
  }

  if (!s[2] && !s[3] && !s[4]) {
    if (c[_indexTip][1] > c[_indexDip][1] &&
        c[_indexDip][1] < c[_indexPip][1]) {
      return 'X';
    }
  }

  if (s[1] && !s[2] && !s[3] && !s[4] && !s[0]) {
    if (_detectZMotion()) return 'Z';
  }

  if (allFingersCurled) {
    if (s[0] && thumbLeftOfIndex()) return 'A';
    if (s[0] && _distance(c[_thumbTip], c[_indexPip]) < 0.06) return 'S';
    if (thumbIndexDist > 0.10 && thumbIndexDist < 0.25 &&
        _distance(c[_thumbTip], c[_pinkyTip]) > 0.15) {
      return 'C';
    }
    if (_distance(c[_thumbTip], c[_indexTip]) < 0.05 &&
        _distance(c[_middleTip], c[_ringTip]) < 0.05) {
      return 'O';
    }

    final tx = c[_thumbTip][0];
    if (rightHand
        ? (c[_indexMcp][0] < tx && tx < c[_middleMcp][0])
        : (c[_middleMcp][0] < tx && tx < c[_indexMcp][0])) {
      return 'T';
    }

    if (rightHand ? c[_thumbTip][0] > c[_pinkyMcp][0] :
        c[_thumbTip][0] < c[_pinkyMcp][0]) {
      return 'M';
    }

    if (rightHand
        ? (c[_middleMcp][0] < tx && tx < c[_ringMcp][0])
        : (c[_ringMcp][0] < tx && tx < c[_middleMcp][0])) {
      return 'N';
    }

    return 'E';
  }

  return null;
}

// Common words / gestures

String? _classifyWords(List<List<double>> c) {
  final s = _fingerStates(c);
  final thumbTip = c[_thumbTip];
  final wrist = c[_wrist];
  final middleTip = c[_middleTip];

  if (s[0] && !s[1] && !s[2] && !s[3] && !s[4]) {
    if (thumbTip[1] < wrist[1] - 0.08) return 'Good (Thumbs Up)';
  }

  if (s[0] && !s[1] && !s[2] && !s[3] && !s[4]) {
    if (thumbTip[1] > wrist[1] + 0.05) return 'Bad (Thumbs Down)';
  }

  if (s[1] && s[2] && s[3] && s[4] && s[0]) {
    if (middleTip[1] < wrist[1]) return 'Hello / Namaste';
  }

  if (s[1] && s[2] && s[3] && s[4] && !s[0]) {
    if (middleTip[1] < wrist[1]) return 'Stop / Wait';
  }

  if (_thumbIndexTouching(c, threshold: 0.06) && s[2] && s[3] && s[4]) {
    return 'OK';
  }

  if (s[0] && s[1] && s[4] && !s[2] && !s[3]) return 'I Love You';
  if (s[0] && s[4] && !s[1] && !s[2] && !s[3]) return 'Call Me';

  if (s[1] && s[2] && !s[3] && !s[4]) {
    if (_dist(c[_indexTip], c[_middleTip]) > 0.05) return 'Peace / Victory';
  }

  if (s[1] && !s[2] && !s[3] && !s[4] && !s[0]) return 'Pointing';
  if (_isFist(c)) return 'Fist (Yes)';
  if (s[1] && s[4] && !s[2] && !s[3] && !s[0]) return 'Rock On';
  if (s[0] && s[1] && s[2] && !s[3] && !s[4]) return 'Three';

  return null;
}



