import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';

enum PhoneCallState { idle, ringing, active, ended }

/// Flutter-side bridge to the Android call architecture.
///
/// Listens to the [EventChannel] for phone state events fired by
/// [CallStateReceiver] (registered in MainActivity) and exposes a simple
/// [onStateChanged] callback so [CallBridgeProvider] can react.
class CallBridgeService {
  static const _control = MethodChannel(AppConfig.callControlChannel);
  static const _events  = EventChannel(AppConfig.callEventsChannel);

  StreamSubscription<dynamic>? _eventSub;

  PhoneCallState _callState = PhoneCallState.idle;
  String _callerNumber = '';

  PhoneCallState get callState => _callState;
  String get callerNumber => _callerNumber;

  /// Called whenever the call state changes.
  VoidCallback? onStateChanged;

  /// Called when relay TTS finishes speaking (so caller STT can re-engage).
  VoidCallback? onTtsDone;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void initialize() {
    debugPrint('[CallBridgeService] initialize — subscribing to call events');
    _eventSub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (dynamic err) {
        debugPrint('[CallBridgeService] event error: $err');
      },
    );
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  // ── Event handler ──────────────────────────────────────────────────────────

  void _onEvent(dynamic raw) {
    debugPrint('[CallBridgeService] raw event: $raw');
    if (raw is! Map) return;

    final event  = raw['event']  as String? ?? '';
    final number = raw['number'] as String? ?? '';

    switch (event) {
      case 'ringing':
        _callState = PhoneCallState.ringing;
        _callerNumber = number;
        onStateChanged?.call();
      case 'active':
        _callState = PhoneCallState.active;
        _callerNumber = number;
        onStateChanged?.call();
      case 'ended':
        _callState = PhoneCallState.ended;
        onStateChanged?.call();
        // Reset to idle after a brief delay so the UI can show "ended"
        Future.delayed(const Duration(seconds: 2), () {
          _callState = PhoneCallState.idle;
          onStateChanged?.call();
        });
      case 'tts_done':
        onTtsDone?.call();
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> startCallMode() async {
    try {
      await _control.invokeMethod<void>('startCallMode');
    } catch (e) {
      debugPrint('[CallBridgeService] startCallMode error: $e');
    }
  }

  Future<void> stopCallMode() async {
    try {
      await _control.invokeMethod<void>('stopCallMode');
    } catch (e) {
      debugPrint('[CallBridgeService] stopCallMode error: $e');
    }
  }

  Future<void> speakForCall(String text) async {
    try {
      await _control.invokeMethod<void>('speakForCall', {'text': text});
    } catch (e) {
      debugPrint('[CallBridgeService] speakForCall error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _control.invokeMethod<void>('stopSpeaking');
    } catch (e) {
      debugPrint('[CallBridgeService] stopSpeaking error: $e');
    }
  }

  /// Switch audio routing for TTS: keep speakerphone ON for acoustic relay.
  Future<void> routeForTts() async {
    try {
      await _control.invokeMethod<void>('routeForTts');
    } catch (e) {
      debugPrint('[CallBridgeService] routeForTts error: $e');
    }
  }

  /// Switch audio routing for STT: speakerphone ON so caller audio reaches the mic.
  Future<void> routeForStt() async {
    try {
      await _control.invokeMethod<void>('routeForStt');
    } catch (e) {
      debugPrint('[CallBridgeService] routeForStt error: $e');
    }
  }
}
