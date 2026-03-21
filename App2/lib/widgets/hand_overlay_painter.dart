import 'package:flutter/material.dart';
import '../models/hand_landmark.dart';

class HandOverlayPainter extends CustomPainter {
  final HandLandmarks? landmarks;
  final Size previewSize;
  final bool isFrontCamera;
  final int sensorOrientation;

  HandOverlayPainter({
    required this.landmarks,
    required this.previewSize,
    this.isFrontCamera = true,
    this.sensorOrientation = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks == null) return;

    final pointPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final thumbPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final needsQuarterTurn =
        size.height > size.width &&
        previewSize.width > previewSize.height &&
        (sensorOrientation == 90 || sensorOrientation == 270);

    // Convert normalized landmarks to screen coordinates.
    // In portrait mode, Android camera frames are often delivered in a
    // quarter-turned sensor space, so we remap them before drawing.
    List<Offset> screenPoints = [];
    for (int i = 0; i < landmarks!.length; i++) {
      final point = landmarks![i];
      double normalizedX = point.x;
      double normalizedY = point.y;

      if (needsQuarterTurn) {
        normalizedX = isFrontCamera ? point.y : 1 - point.y;
        normalizedY = point.x;
      } else if (isFrontCamera) {
        normalizedX = 1 - normalizedX;
      }

      final x = normalizedX * size.width;
      final y = normalizedY * size.height;

      screenPoints.add(Offset(x, y));
    }

    // Draw connections
    for (final connection in HandLandmarks.connections) {
      final start = connection[0];
      final end = connection[1];

      // Use different color for thumb
      final paint = (start <= 4 && end <= 4) ? thumbPaint : linePaint;

      canvas.drawLine(screenPoints[start], screenPoints[end], paint);
    }

    // Draw landmark points
    for (int i = 0; i < screenPoints.length; i++) {
      // Wrist point is larger
      final radius = i == 0 ? 6.0 : 4.0;
      canvas.drawCircle(screenPoints[i], radius, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandOverlayPainter oldDelegate) {
    return landmarks != oldDelegate.landmarks;
  }
}

class HandOverlayWidget extends StatelessWidget {
  final HandLandmarks? landmarks;
  final Size previewSize;
  final bool isFrontCamera;
  final int sensorOrientation;

  const HandOverlayWidget({
    super.key,
    required this.landmarks,
    required this.previewSize,
    this.isFrontCamera = true,
    this.sensorOrientation = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: HandOverlayPainter(
        landmarks: landmarks,
        previewSize: previewSize,
        isFrontCamera: isFrontCamera,
        sensorOrientation: sensorOrientation,
      ),
      size: Size.infinite,
    );
  }
}
