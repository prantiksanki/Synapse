import 'dart:async';
import 'package:flutter/services.dart';

enum WatchCaptureStatus { idle, capturing, silence, stopped, error }

/// Flutter-side bridge for the Watch Video system audio capture feature.
///
/// Mirrors [CallBridgeService] in structure:
///  - MethodChannel  "synapse/watch_control"  → sends commands to Kotlin
///  - EventChannel   "synapse/watch_events"   ← receives events from Kotlin
///
/// Events received from Kotlin:
///   { "event": "projection_granted" }
///   { "event": "projection_denied" }
///   { "event": "transcript", "text": "...", "isFinal": true }
///   { "event": "status", "value": "capturing" | "silence" | "stopped" }
///   { "event": "error", "message": "..." }
class SystemAudioService {
  static const _control = MethodChannel('synapse/watch_control');
  static const _events  = EventChannel('synapse/watch_events');

  StreamSubscription<dynamic>? _subscription;

  // ── Callbacks ──────────────────────────────────────────────────────────────
  void Function(String text, bool isFinal)? onTranscript;
  void Function(WatchCaptureStatus)? onStatus;
  void Function(String message)? onError;
  VoidCallback? onProjectionGranted;
  VoidCallback? onProjectionDenied;

  WatchCaptureStatus _status = WatchCaptureStatus.idle;
  WatchCaptureStatus get status => _status;
  bool get isCapturing => _status == WatchCaptureStatus.capturing;

  // ── Initialization ─────────────────────────────────────────────────────────

  void initialize() {
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (dynamic e) {
        _status = WatchCaptureStatus.error;
        onError?.call(e.toString());
      },
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);
    final type = map['event'] as String? ?? '';

    switch (type) {
      case 'projection_granted':
        onProjectionGranted?.call();
        break;
      case 'projection_denied':
        onProjectionDenied?.call();
        break;
      case 'transcript':
        final text    = map['text'] as String? ?? '';
        final isFinal = map['isFinal'] as bool? ?? true;
        if (text.isNotEmpty) onTranscript?.call(text, isFinal);
        break;
      case 'status':
        final value = map['value'] as String? ?? '';
        _status = switch (value) {
          'capturing' => WatchCaptureStatus.capturing,
          'silence'   => WatchCaptureStatus.silence,
          'stopped'   => WatchCaptureStatus.stopped,
          _           => WatchCaptureStatus.idle,
        };
        onStatus?.call(_status);
        break;
      case 'error':
        _status = WatchCaptureStatus.error;
        onError?.call(map['message'] as String? ?? 'Unknown error');
        break;
      default:
        break;
    }
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Shows the system "Start recording?" MediaProjection consent dialog.
  Future<void> requestMediaProjectionConsent() async {
    await _control.invokeMethod('requestMediaProjectionConsent');
  }

  /// Starts [SystemAudioCaptureService] using the stored projection token.
  Future<void> startCapture() async {
    await _control.invokeMethod('startCapture');
  }

  /// Stops the capture service.
  Future<void> stopCapture() async {
    await _control.invokeMethod('stopCapture');
    _status = WatchCaptureStatus.stopped;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    onTranscript = null;
    onStatus     = null;
    onError      = null;
    onProjectionGranted = null;
    onProjectionDenied  = null;
  }
}
