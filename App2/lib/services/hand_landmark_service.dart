import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

class HandLandmarkService {
  HandLandmarkerPlugin? _handLandmarker;
  bool _isInitialized = false;
  bool _isProcessing = false;
  DateTime _lastProcessTime = DateTime.now();
  int _sensorOrientation = 0;

  // Minimum time between frame processing (for frame skipping)
  static const int _minFrameIntervalMs = 33; // ~30 FPS max

  bool get isInitialized => _isInitialized;

  void initialize({int sensorOrientation = 0}) {
    try {
      _sensorOrientation = sensorOrientation;
      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.GPU,
      );
      _isInitialized = true;
      debugPrint('HandLandmarker initialized successfully');
    } catch (e) {
      debugPrint('Error initializing HandLandmarker: $e');
      rethrow;
    }
  }

  void setSensorOrientation(int orientation) {
    _sensorOrientation = orientation;
  }

  List<List<double>>? processImage(CameraImage image) {
    if (!_isInitialized || _handLandmarker == null) {
      return null;
    }

    // Frame skipping: don't process if still processing previous frame
    if (_isProcessing) {
      return null;
    }

    // Frame skipping: enforce minimum interval between frames
    final now = DateTime.now();
    if (now.difference(_lastProcessTime).inMilliseconds < _minFrameIntervalMs) {
      return null;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      final result = _handLandmarker!.detect(image, _sensorOrientation);

      if (result.isEmpty) {
        return null;
      }

      // Extract landmarks from the first detected hand
      // Each hand has 21 landmarks with x, y, z coordinates (normalized 0-1)
      final handLandmarks = result.first;

      // Convert to list of [x, y] pairs (we only need 2D for classification)
      final landmarks = <List<double>>[];
      for (final landmark in handLandmarks.landmarks) {
        landmarks.add([landmark.x, landmark.y]);
      }

      return landmarks;
    } catch (e) {
      debugPrint('Error processing image: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Process a JPEG frame received from the Raspberry Pi over Socket.IO.
  /// Decodes JPEG → RGBA → converts to YUV420 → constructs a real
  /// CameraImage via the platform interface so the hand_landmarker plugin
  /// can process it identically to a live camera frame.
  Future<List<List<double>>?> processJpeg(Uint8List jpeg) async {
    if (!_isInitialized || _handLandmarker == null) return null;
    if (_isProcessing) return null;

    final now = DateTime.now();
    if (now.difference(_lastProcessTime).inMilliseconds < _minFrameIntervalMs) {
      return null;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      // 1. Decode JPEG → RGBA pixels via dart:ui
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      uiImage.dispose();
      if (byteData == null) return null;

      final rgba = byteData.buffer.asUint8List();
      final width = uiImage.width;
      final height = uiImage.height;
      final pixels = width * height;

      // 2. Convert RGBA → YUV420 (I420: Y plane full-res, U/V half-res)
      final yPlane = Uint8List(pixels);
      final uPlane = Uint8List((width ~/ 2) * (height ~/ 2));
      final vPlane = Uint8List((width ~/ 2) * (height ~/ 2));

      for (var row = 0; row < height; row++) {
        for (var col = 0; col < width; col++) {
          final i = (row * width + col) * 4;
          final r = rgba[i];
          final g = rgba[i + 1];
          final b = rgba[i + 2];

          // BT.601 full-range
          yPlane[row * width + col] =
              ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;

          if (row.isEven && col.isEven) {
            final uvIdx = (row ~/ 2) * (width ~/ 2) + col ~/ 2;
            uPlane[uvIdx] = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
            vPlane[uvIdx] = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
          }
        }
      }

      // 3. Build CameraImage via the public platform-interface constructors
      final cameraImage = CameraImage.fromPlatformInterface(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
          width: width,
          height: height,
          planes: [
            CameraImagePlane(
              bytes: yPlane,
              bytesPerRow: width,
              bytesPerPixel: 1,
            ),
            CameraImagePlane(
              bytes: uPlane,
              bytesPerRow: width ~/ 2,
              bytesPerPixel: 1,
            ),
            CameraImagePlane(
              bytes: vPlane,
              bytesPerRow: width ~/ 2,
              bytesPerPixel: 1,
            ),
          ],
        ),
      );

      // 4. Run same landmark detection as processImage()
      final result = _handLandmarker!.detect(cameraImage, _sensorOrientation);
      if (result.isEmpty) return null;

      final landmarks = <List<double>>[];
      for (final lm in result.first.landmarks) {
        landmarks.add([lm.x, lm.y]);
      }
      return landmarks;
    } catch (e) {
      debugPrint('[HandLandmarkService] processJpeg error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    _handLandmarker?.dispose();
    _handLandmarker = null;
    _isInitialized = false;
  }
}
