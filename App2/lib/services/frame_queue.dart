import 'dart:collection';
import 'dart:typed_data';

/// A bounded JPEG frame queue that decouples Socket.IO frame events from the
/// MediaPipe pipeline. Drops the oldest frame when full to prevent memory
/// blowup at 30fps.
class FrameQueue {
  final int maxDepth;
  final Queue<Uint8List> _queue = Queue();
  bool _processing = false;

  /// Called when a frame is ready to be processed. The consumer MUST call
  /// [frameConsumed] when done so the next frame can be dispatched.
  void Function(Uint8List jpeg)? onFrame;

  FrameQueue({this.maxDepth = 3});

  /// Push a JPEG frame. If the queue is full, the oldest frame is dropped.
  void push(Uint8List jpegBytes) {
    if (_queue.length >= maxDepth) {
      _queue.removeFirst();
    }
    _queue.addLast(jpegBytes);
    _drain();
  }

  /// Call after the consumer finishes processing the last dispatched frame.
  void frameConsumed() {
    _processing = false;
    _drain();
  }

  void _drain() {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    final frame = _queue.removeFirst();
    onFrame?.call(frame);
  }

  void clear() {
    _queue.clear();
    _processing = false;
  }
}
