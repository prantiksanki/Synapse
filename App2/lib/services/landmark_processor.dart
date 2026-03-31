import 'dart:math';

/// Preprocesses hand landmarks for the keypoint classifier.
/// This is a direct port from the Python implementation in app.py lines 246-270.
class LandmarkProcessor {
  /// Converts normalized landmarks (0-1) to pixel coordinates
  static List<List<int>> convertToPixelCoords(
    List<List<double>> normalizedLandmarks,
    int imageWidth,
    int imageHeight,
  ) {
    return normalizedLandmarks.map((point) {
      return [
        (point[0] * imageWidth).round(),
        (point[1] * imageHeight).round(),
      ];
    }).toList();
  }

  /// Preprocesses landmarks for the keypoint classifier.
  ///
  /// Steps:
  /// 1. Make coordinates relative to wrist (landmark[0])
  /// 2. Flatten to 1D list
  /// 3. Normalize by max absolute value
  ///
  /// Returns a list of 42 normalized floats.
  static List<double> preProcessLandmark(List<List<int>> landmarkList) {
    if (landmarkList.length != 21) {
      throw ArgumentError('Expected 21 landmarks, got ${landmarkList.length}');
    }

    // 1. Copy landmarks
    final temp = landmarkList.map((p) => [p[0], p[1]]).toList();

    // 2. Make relative to wrist (index 0)
    final baseX = temp[0][0];
    final baseY = temp[0][1];
    for (var i = 0; i < temp.length; i++) {
      temp[i][0] -= baseX;
      temp[i][1] -= baseY;
    }

    // 3. Flatten to 1D list
    final flattened = <double>[];
    for (final point in temp) {
      flattened.add(point[0].toDouble());
      flattened.add(point[1].toDouble());
    }

    // 4. Normalize by max absolute value
    final maxValue = flattened.map((v) => v.abs()).reduce(max);
    if (maxValue > 0) {
      for (var i = 0; i < flattened.length; i++) {
        flattened[i] /= maxValue;
      }
    }

    return flattened; // 42 normalized floats
  }

  /// Preprocesses normalized landmarks directly without pixel conversion.
  /// This is more efficient when we don't need pixel coordinates.
  static List<double> preProcessNormalizedLandmarks(
    List<List<double>> normalizedLandmarks,
  ) {
    if (normalizedLandmarks.length != 21) {
      throw ArgumentError(
        'Expected 21 landmarks, got ${normalizedLandmarks.length}',
      );
    }

    // 1. Copy and work with normalized coordinates
    final temp = normalizedLandmarks.map((p) => [p[0], p[1]]).toList();

    // 2. Make relative to wrist (index 0)
    final baseX = temp[0][0];
    final baseY = temp[0][1];
    for (var i = 0; i < temp.length; i++) {
      temp[i][0] -= baseX;
      temp[i][1] -= baseY;
    }

    // 3. Flatten to 1D list
    final flattened = <double>[];
    for (final point in temp) {
      flattened.add(point[0]);
      flattened.add(point[1]);
    }

    // 4. Normalize by max absolute value
    final maxValue = flattened.map((v) => v.abs()).reduce(max);
    if (maxValue > 0) {
      for (var i = 0; i < flattened.length; i++) {
        flattened[i] /= maxValue;
      }
    }

    return flattened; // 42 normalized floats
  }
}
