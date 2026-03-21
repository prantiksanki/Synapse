// mediapipe_service.dart — Hand landmark detection via MediaPipe.
//
// This service bridges the Flutter camera stream to MediaPipe's hand
// landmark model. It returns 21 (x, y) landmark coordinates normalised
// relative to the wrist (landmark 0) so the gesture classifier receives
// scale-invariant, position-invariant input.
//
// Integration path:
//   • On-device: the native Android side can use the MediaPipe Tasks SDK
//     (google_mlkit_commons) and report landmarks back via the platform channel.
//   • Fallback: if the platform channel is unavailable (e.g. simulator),
//     a mock set of landmarks is returned so the rest of the pipeline can
//     still be exercised.

import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Wraps the MediaPipe hand-landmark platform channel.
///
/// Output: 21 landmarks, each as [x, y] in pixel space, then normalised
/// so landmark 0 (wrist) becomes the origin.
class MediaPipeService {
  // -------------------------------------------------------------------------
  // Platform channel
  // -------------------------------------------------------------------------

  static const _channel = MethodChannel('com.synapse.app/mediapipe');

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Process a [CameraImage] and return normalised hand landmarks.
  ///
  /// Returns a list of 21 (x, y) pairs — i.e. a flat list of 42 doubles
  /// where index [i*2] = x and [i*2+1] = y for landmark i.
  ///
  /// Returns an empty list if no hand is detected.
  Future<List<double>> detectLandmarks(CameraImage image) async {
    try {
      final bytes = _convertYuv420ToNv21(image);

      final result = await _channel.invokeMethod<List<dynamic>>(
        'detectLandmarks',
        {
          'bytes': bytes,
          'width': image.width,
          'height': image.height,
          'rotation': 90, // Portrait orientation offset
        },
      );

      if (result == null || result.isEmpty) return [];

      final raw = result.cast<double>();
      return _normalizeLandmarks(raw);
    } on MissingPluginException {
      // Platform channel not registered — use mock data for development
      dev.log(
        'MediaPipe channel not available; using mock landmarks.',
        name: 'MediaPipeService',
      );
      return _mockLandmarks();
    } on PlatformException catch (e) {
      dev.log('MediaPipe platform error: ${e.message}', name: 'MediaPipeService');
      return [];
    } catch (e) {
      dev.log('MediaPipe unexpected error: $e', name: 'MediaPipeService');
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // Image format conversion
  // -------------------------------------------------------------------------

  /// Convert a YUV420 [CameraImage] to a flat NV21 byte buffer.
  ///
  /// MediaPipe on Android expects NV21 (Y plane followed by interleaved VU).
  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final int width  = image.width;
    final int height = image.height;
    final int ySize  = width * height;
    final int uvSize = width * height ~/ 2;

    final nv21 = Uint8List(ySize + uvSize);

    // --- Y plane ---
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final int yRowStride = yPlane.bytesPerRow;

    for (int row = 0; row < height; row++) {
      final int srcOffset = row * yRowStride;
      final int dstOffset = row * width;
      final int copyLen   = width.clamp(0, yBytes.length - srcOffset);
      nv21.setRange(dstOffset, dstOffset + copyLen,
          yBytes.sublist(srcOffset, srcOffset + copyLen));
    }

    // --- UV planes → interleaved VU ---
    if (image.planes.length >= 3) {
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;
      final int uvRowStride    = uPlane.bytesPerRow;
      final int uvPixelStride  = uPlane.bytesPerPixel ?? 1;
      final int uvHeight       = height ~/ 2;
      final int uvWidth        = width  ~/ 2;

      int dstIdx = ySize;
      for (int row = 0; row < uvHeight; row++) {
        for (int col = 0; col < uvWidth; col++) {
          final int srcIdx = row * uvRowStride + col * uvPixelStride;
          if (srcIdx < vBytes.length) nv21[dstIdx++] = vBytes[srcIdx];
          if (srcIdx < uBytes.length) nv21[dstIdx++] = uBytes[srcIdx];
        }
      }
    }

    return nv21;
  }

  // -------------------------------------------------------------------------
  // Landmark normalisation
  // -------------------------------------------------------------------------

  /// Normalise 42 raw landmark values (x0,y0, x1,y1, …, x20,y20) so that:
  ///   • The wrist (landmark 0) becomes (0, 0)
  ///   • All coordinates are divided by the scale factor (hand bounding-box
  ///     diagonal) making the representation scale-invariant.
  List<double> _normalizeLandmarks(List<double> raw) {
    if (raw.length != 42) return raw;

    // Wrist is landmark 0
    final double wristX = raw[0];
    final double wristY = raw[1];

    // Compute bounding box for scale normalisation
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (int i = 0; i < 42; i += 2) {
      final x = raw[i]   - wristX;
      final y = raw[i+1] - wristY;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    // Diagonal of bounding box as scale factor (avoid division by zero)
    final double scale = _hypot(maxX - minX, maxY - minY);
    if (scale == 0) return List.filled(42, 0.0);

    final normalized = List<double>.filled(42, 0.0);
    for (int i = 0; i < 42; i += 2) {
      normalized[i]   = (raw[i]   - wristX) / scale;
      normalized[i+1] = (raw[i+1] - wristY) / scale;
    }
    return normalized;
  }

  double _hypot(double a, double b) => (a * a + b * b <= 0)
      ? 0
      : (a * a + b * b < 1e-12 ? 0 : _sqrt(a * a + b * b));

  double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    for (int i = 0; i < 40; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  // -------------------------------------------------------------------------
  // Mock landmarks for testing without a real camera / native channel
  // -------------------------------------------------------------------------

  /// Returns a static "open hand" landmark pattern for pipeline testing.
  List<double> _mockLandmarks() {
    // 21 landmarks representing a rough open-palm gesture,
    // already normalised (wrist at origin).
    return [
      // Wrist
      0.0,   0.0,
      // Thumb CMC → tip
      0.05,  0.12,  0.08,  0.20,  0.11,  0.28,  0.13,  0.35,
      // Index MCP → tip
      0.06,  0.40,  0.06,  0.55,  0.06,  0.65,  0.06,  0.72,
      // Middle MCP → tip
      0.00,  0.42,  0.00,  0.57,  0.00,  0.67,  0.00,  0.74,
      // Ring MCP → tip
      -0.06, 0.40, -0.06,  0.55, -0.06,  0.65, -0.06,  0.72,
      // Pinky MCP → tip
      -0.12, 0.38, -0.13,  0.50, -0.13,  0.59, -0.13,  0.65,
    ];
  }
}
