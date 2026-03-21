import 'package:camera/camera.dart';
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

  void dispose() {
    _handLandmarker?.dispose();
    _handLandmarker = null;
    _isInitialized = false;
  }
}
