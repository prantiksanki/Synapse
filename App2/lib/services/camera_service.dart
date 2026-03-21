import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isStreaming = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;

  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Use the front camera for sign language detection
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      rethrow;
    }
  }

  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }

    if (_isStreaming) {
      return;
    }

    await _controller!.startImageStream(onImage);
    _isStreaming = true;
  }

  Future<void> stopImageStream() async {
    if (!_isStreaming || _controller == null) {
      return;
    }

    await _controller!.stopImageStream();
    _isStreaming = false;
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  int get sensorOrientation => _controller?.description.sensorOrientation ?? 0;

  CameraLensDirection get lensDirection =>
      _controller?.description.lensDirection ?? CameraLensDirection.front;
}
