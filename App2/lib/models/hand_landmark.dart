/// Represents a single hand landmark point.
class HandLandmarkPoint {
  final double x;
  final double y;
  final double? z;

  const HandLandmarkPoint({
    required this.x,
    required this.y,
    this.z,
  });

  /// Convert to pixel coordinates
  List<int> toPixelCoords(int imageWidth, int imageHeight) {
    return [
      (x * imageWidth).round(),
      (y * imageHeight).round(),
    ];
  }
}

/// Represents all 21 hand landmarks.
class HandLandmarks {
  final List<HandLandmarkPoint> points;

  const HandLandmarks(this.points);

  factory HandLandmarks.fromList(List<List<double>> landmarks) {
    return HandLandmarks(
      landmarks.map((p) => HandLandmarkPoint(
        x: p[0],
        y: p[1],
        z: p.length > 2 ? p[2] : null,
      )).toList(),
    );
  }

  /// Get landmarks as list of [x, y] pairs
  List<List<double>> toList() {
    return points.map((p) => [p.x, p.y]).toList();
  }

  /// Hand landmark connections for drawing skeleton
  static const List<List<int>> connections = [
    // Thumb
    [0, 1], [1, 2], [2, 3], [3, 4],
    // Index finger
    [0, 5], [5, 6], [6, 7], [7, 8],
    // Middle finger
    [0, 9], [9, 10], [10, 11], [11, 12],
    // Ring finger
    [0, 13], [13, 14], [14, 15], [15, 16],
    // Pinky
    [0, 17], [17, 18], [18, 19], [19, 20],
    // Palm
    [5, 9], [9, 13], [13, 17],
  ];

  int get length => points.length;

  HandLandmarkPoint operator [](int index) => points[index];
}
