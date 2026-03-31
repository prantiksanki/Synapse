import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Extracts a 320×320 RGB hand crop from a [CameraImage] using landmark bounds.
///
/// Supports YUV420 (Android) and BGRA8888 (iOS) formats.
class HandCropService {
  static const int _outputSize = 320;
  static const int _pad = 40;

  static bool _initialized = false;

  static void initialize() {
    _initialized = true;
  }

  /// Returns a 160×160×3 RGB [Uint8List] crop, or null on failure.
  static Uint8List? extractCrop(
    CameraImage image,
    List<List<double>> normalizedLandmarks,
  ) {
    if (!_initialized) return null;

    try {
      final w = image.width;
      final h = image.height;

      double xMin = double.infinity, xMax = double.negativeInfinity;
      double yMin = double.infinity, yMax = double.negativeInfinity;
      for (final lm in normalizedLandmarks) {
        final px = lm[0] * w;
        final py = lm[1] * h;
        if (px < xMin) xMin = px;
        if (px > xMax) xMax = px;
        if (py < yMin) yMin = py;
        if (py > yMax) yMax = py;
      }

      final x1 = (xMin - _pad).clamp(0, w - 1).toInt();
      final y1 = (yMin - _pad).clamp(0, h - 1).toInt();
      final x2 = (xMax + _pad).clamp(0, w - 1).toInt();
      final y2 = (yMax + _pad).clamp(0, h - 1).toInt();

      final cropW = x2 - x1;
      final cropH = y2 - y1;
      if (cropW <= 0 || cropH <= 0) return null;

      Uint8List? rgb;
      final fmt = image.format.group;
      if (fmt == ImageFormatGroup.yuv420) {
        rgb = _yuv420CropToRgb(image, x1, y1, cropW, cropH);
      } else if (fmt == ImageFormatGroup.bgra8888) {
        rgb = _bgraCropToRgb(image, x1, y1, cropW, cropH);
      } else {
        debugPrint('HandCropService: unsupported format $fmt');
        return null;
      }

      return _resizeBilinear(rgb, cropW, cropH, _outputSize, _outputSize);
    } catch (e) {
      debugPrint('HandCropService.extractCrop error: $e');
      return null;
    }
  }

  /// Returns the bounding box [x1, y1, x2, y2] in pixel coords for the given
  /// landmarks, without performing the crop. Used for motion-skip detection.
  static List<int>? boundingBox(
    CameraImage image,
    List<List<double>> normalizedLandmarks,
  ) {
    try {
      final w = image.width;
      final h = image.height;
      double xMin = double.infinity, xMax = double.negativeInfinity;
      double yMin = double.infinity, yMax = double.negativeInfinity;
      for (final lm in normalizedLandmarks) {
        final px = lm[0] * w;
        final py = lm[1] * h;
        if (px < xMin) xMin = px;
        if (px > xMax) xMax = px;
        if (py < yMin) yMin = py;
        if (py > yMax) yMax = py;
      }
      return [
        (xMin - _pad).clamp(0, w - 1).toInt(),
        (yMin - _pad).clamp(0, h - 1).toInt(),
        (xMax + _pad).clamp(0, w - 1).toInt(),
        (yMax + _pad).clamp(0, h - 1).toInt(),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Extracts a 160×160 RGB crop from a JPEG byte buffer (Pi camera path).
  static Future<Uint8List?> extractCropFromJpeg(
    Uint8List jpeg,
    List<List<double>> normalizedLandmarks,
  ) async {
    if (!_initialized) return null;
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = uiImage.width;
      final h = uiImage.height;
      uiImage.dispose();
      if (byteData == null) return null;

      final rgba = byteData.buffer.asUint8List();

      double xMin = double.infinity, xMax = double.negativeInfinity;
      double yMin = double.infinity, yMax = double.negativeInfinity;
      for (final lm in normalizedLandmarks) {
        final px = lm[0] * w;
        final py = lm[1] * h;
        if (px < xMin) xMin = px;
        if (px > xMax) xMax = px;
        if (py < yMin) yMin = py;
        if (py > yMax) yMax = py;
      }

      final x1 = (xMin - _pad).clamp(0, w - 1).toInt();
      final y1 = (yMin - _pad).clamp(0, h - 1).toInt();
      final x2 = (xMax + _pad).clamp(0, w - 1).toInt();
      final y2 = (yMax + _pad).clamp(0, h - 1).toInt();
      final cw = x2 - x1;
      final ch = y2 - y1;
      if (cw <= 0 || ch <= 0) return null;

      final rgb = Uint8List(cw * ch * 3);
      var idx = 0;
      for (var row = 0; row < ch; row++) {
        for (var col = 0; col < cw; col++) {
          final base = ((y1 + row) * w + (x1 + col)) * 4;
          rgb[idx++] = rgba[base];
          rgb[idx++] = rgba[base + 1];
          rgb[idx++] = rgba[base + 2];
        }
      }

      return _resizeBilinear(rgb, cw, ch, _outputSize, _outputSize);
    } catch (e) {
      debugPrint('HandCropService.extractCropFromJpeg error: $e');
      return null;
    }
  }

  // ── YUV420 → RGB crop ────────────────────────────────────────────────────────

  static Uint8List _yuv420CropToRgb(
    CameraImage img,
    int x1,
    int y1,
    int cw,
    int ch,
  ) {
    final yPlane = img.planes[0].bytes;
    final uPlane = img.planes[1].bytes;
    final vPlane = img.planes[2].bytes;
    final yRowStride = img.planes[0].bytesPerRow;
    final uvRowStride = img.planes[1].bytesPerRow;
    final uvPixelStride = img.planes[1].bytesPerPixel ?? 1;

    final out = Uint8List(cw * ch * 3);
    var idx = 0;

    for (var row = 0; row < ch; row++) {
      for (var col = 0; col < cw; col++) {
        final px = x1 + col;
        final py = y1 + row;

        final yVal = yPlane[py * yRowStride + px];
        final uvRow = (py ~/ 2) * uvRowStride;
        final uvCol = (px ~/ 2) * uvPixelStride;
        final uVal = uPlane[uvRow + uvCol];
        final vVal = vPlane[uvRow + uvCol];

        final yp = yVal - 16;
        final up = uVal - 128;
        final vp = vVal - 128;

        final r = ((298 * yp + 409 * vp + 128) >> 8).clamp(0, 255);
        final g = ((298 * yp - 100 * up - 208 * vp + 128) >> 8).clamp(0, 255);
        final b = ((298 * yp + 516 * up + 128) >> 8).clamp(0, 255);

        out[idx++] = r;
        out[idx++] = g;
        out[idx++] = b;
      }
    }
    return out;
  }

  // ── BGRA8888 → RGB crop ──────────────────────────────────────────────────────

  static Uint8List _bgraCropToRgb(
    CameraImage img,
    int x1,
    int y1,
    int cw,
    int ch,
  ) {
    final bytes = img.planes[0].bytes;
    final rowStride = img.planes[0].bytesPerRow;
    final out = Uint8List(cw * ch * 3);
    var idx = 0;

    for (var row = 0; row < ch; row++) {
      for (var col = 0; col < cw; col++) {
        final base = (y1 + row) * rowStride + (x1 + col) * 4;
        out[idx++] = bytes[base + 2]; // R
        out[idx++] = bytes[base + 1]; // G
        out[idx++] = bytes[base];     // B
      }
    }
    return out;
  }

  // ── Bilinear resize ──────────────────────────────────────────────────────────

  static Uint8List _resizeBilinear(
    Uint8List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final dst = Uint8List(dstW * dstH * 3);
    final xScale = srcW / dstW;
    final yScale = srcH / dstH;

    for (var dy = 0; dy < dstH; dy++) {
      final sy = dy * yScale;
      final sy0 = sy.floor().clamp(0, srcH - 1);
      final sy1 = (sy0 + 1).clamp(0, srcH - 1);
      final fy = sy - sy0;

      for (var dx = 0; dx < dstW; dx++) {
        final sx = dx * xScale;
        final sx0 = sx.floor().clamp(0, srcW - 1);
        final sx1 = (sx0 + 1).clamp(0, srcW - 1);
        final fx = sx - sx0;

        for (var c = 0; c < 3; c++) {
          final p00 = src[(sy0 * srcW + sx0) * 3 + c];
          final p01 = src[(sy0 * srcW + sx1) * 3 + c];
          final p10 = src[(sy1 * srcW + sx0) * 3 + c];
          final p11 = src[(sy1 * srcW + sx1) * 3 + c];

          final val = (p00 * (1 - fx) * (1 - fy) +
                  p01 * fx * (1 - fy) +
                  p10 * (1 - fx) * fy +
                  p11 * fx * fy)
              .round()
              .clamp(0, 255);

          dst[(dy * dstW + dx) * 3 + c] = val;
        }
      }
    }
    return dst;
  }
}
