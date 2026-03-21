// camera_service.dart — Manages camera initialization and frame streaming.
//
// Wraps the Flutter `camera` package to provide a clean interface for:
//   - Selecting the back camera
//   - Streaming CameraImage frames to the ML pipeline
//   - Throttling frames to a target FPS to avoid overwhelming inference

import 'dart:async';
import 'dart:developer' as dev;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Manages camera lifecycle and delivers frames to the gesture-recognition pipeline.
class CameraService {
  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------

  /// Target frame rate for the ML pipeline (lower = less CPU/GPU load).
  static const int _targetFps = 20;

  /// Minimum duration between processed frames.
  static const Duration _frameInterval = Duration(milliseconds: 1000 ~/ _targetFps);

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isStreaming = false;
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  // FPS tracking
  int _frameCount = 0;
  DateTime _fpsWindowStart = DateTime.now();
  int _currentFps = 0;
  int get currentFps => _currentFps;

  // Callback for FPS updates
  ValueChanged<int>? onFpsUpdated;

  /// Returns the underlying [CameraController] (null until [initialize] is called).
  CameraController? get controller => _controller;

  /// Whether the camera is actively streaming frames.
  bool get isStreaming => _isStreaming;

  /// Whether the controller is initialized and preview is ready.
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  /// Discover cameras and initialize the back-facing camera controller.
  ///
  /// Must be called (and awaited) before [startStream].
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw CameraException('no_cameras', 'No cameras found on this device.');
      }

      // Prefer the back camera; fall back to whatever is available
      final CameraDescription camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high, // 1280×720 — good balance of detail and speed
        enableAudio: false,     // Audio not needed for sign detection
        imageFormatGroup: ImageFormatGroup.yuv420, // Required by MediaPipe
      );

      await _controller!.initialize();
      dev.log('Camera initialized: ${camera.name} (${camera.lensDirection})',
          name: 'CameraService');
    } catch (e) {
      dev.log('Camera initialization failed: $e', name: 'CameraService', level: 900);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Frame streaming
  // -------------------------------------------------------------------------

  /// Begin delivering YUV420 frames to [onFrame] at up to [_targetFps].
  ///
  /// Frames that arrive faster than the target interval are silently dropped
  /// to prevent the inference pipeline from queueing indefinitely.
  Future<void> startStream(void Function(CameraImage image) onFrame) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('CameraService.initialize() must be called first.');
    }
    if (_isStreaming) return;

    _isStreaming = true;
    _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
    _frameCount = 0;
    _fpsWindowStart = DateTime.now();

    await _controller!.startImageStream((CameraImage image) {
      final now = DateTime.now();

      // ---- FPS counter ----
      _frameCount++;
      final elapsed = now.difference(_fpsWindowStart);
      if (elapsed.inMilliseconds >= 1000) {
        _currentFps = (_frameCount * 1000 / elapsed.inMilliseconds).round();
        _frameCount = 0;
        _fpsWindowStart = now;
        onFpsUpdated?.call(_currentFps);
      }

      // ---- Frame throttle ----
      if (now.difference(_lastFrameTime) < _frameInterval) return;
      _lastFrameTime = now;

      onFrame(image);
    });

    dev.log('Image stream started (target $_targetFps fps).', name: 'CameraService');
  }

  /// Stop the image stream but keep the camera preview alive.
  Future<void> stopStream() async {
    if (!_isStreaming) return;
    try {
      await _controller?.stopImageStream();
    } catch (e) {
      dev.log('stopImageStream error (may be already stopped): $e',
          name: 'CameraService');
    } finally {
      _isStreaming = false;
    }
    dev.log('Image stream stopped.', name: 'CameraService');
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Stop the stream and release the camera hardware.
  Future<void> dispose() async {
    await stopStream();
    await _controller?.dispose();
    _controller = null;
    dev.log('CameraService disposed.', name: 'CameraService');
  }
}
