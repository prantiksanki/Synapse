import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../config/app_config.dart';
import '../models/connection_state.dart';
import '../models/hw_info.dart';

/// Manages the Socket.IO connection to the SYNAPSE Raspberry Pi hardware device.
///
/// Connection policy:
/// - Only attempts TCP connect when the device has a WiFi connection.
/// - If connection fails or drops, waits [_retryDelay] before retrying.
/// - Retry delay doubles on each failure (3s → 6s → 12s → max 30s) so the
///   badge stays stable instead of flickering rapidly.
/// - While on mobile data / no network, stays in [HwConnectionStatus.disconnected]
///   silently without retrying.
class HardwareService {
  socket_io.Socket? _socket;
  Timer? _retryTimer;
  Timer? _pingTimer;
  int _pingTimestamp = 0;
  Duration _retryDelay = const Duration(seconds: 3);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Current connection status — listen with addListener.
  final ValueNotifier<HwStatus> status =
      ValueNotifier(const HwStatus.disconnected());

  /// Called when a JPEG frame arrives from the hardware camera.
  void Function(Uint8List jpeg)? onFrame;

  /// Called when PCM audio arrives from the hardware microphone.
  void Function(Uint8List pcm)? onAudio;

  bool _disposed = false;
  bool _connecting = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Start monitoring connectivity and connect when WiFi is available.
  Future<void> connect() async {
    if (_disposed) return;

    // Listen for connectivity changes — reconnect when WiFi comes back
    _connectivitySub ??= Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Check current network state immediately
    final results = await Connectivity().checkConnectivity();
    if (_hasWifi(results)) {
      await _tryConnect();
    } else {
      // Not on WiFi — stay disconnected silently, no retry loop
      _setStatus(const HwStatus.disconnected());
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  bool _hasWifi(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    if (_hasWifi(results)) {
      // WiFi appeared — attempt connection after a short settle delay
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 1), () {
        if (!_disposed && !_connecting && _socket?.connected != true) {
          _retryDelay = const Duration(seconds: 3); // reset backoff
          _tryConnect();
        }
      });
    } else {
      // Lost WiFi — tear down socket, stay disconnected quietly
      _cancelSocket();
      _retryTimer?.cancel();
      _setStatus(const HwStatus.disconnected());
    }
  }

  Future<void> _tryConnect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _setStatus(HwStatus(status: HwConnectionStatus.connecting));

    try {
      _socket?.dispose();
      _socket = socket_io.io(
        AppConfig.hwSocketUrl,
        socket_io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .disableReconnection() // we handle reconnect manually
            .setTimeout(4000)
            .build(),
      );
      _setupListeners();
      _socket!.connect();
    } catch (e) {
      debugPrint('[HardwareService] connect error: $e');
      _connecting = false;
      _setStatus(const HwStatus.disconnected());
      _scheduleRetry();
    }
  }

  void _setupListeners() {
    final socket = _socket!;

    socket.onConnect((_) {
      debugPrint('[HardwareService] connected');
      _connecting = false;
      _retryDelay = const Duration(seconds: 3); // reset backoff on success
      _setStatus(HwStatus(status: HwConnectionStatus.connected));
      _startPingTimer();
    });

    socket.onDisconnect((_) {
      debugPrint('[HardwareService] disconnected');
      _connecting = false;
      _pingTimer?.cancel();
      _setStatus(const HwStatus.disconnected());
      if (!_disposed) _scheduleRetry();
    });

    socket.onError((e) {
      debugPrint('[HardwareService] socket error: $e');
    });

    socket.onConnectError((e) {
      debugPrint('[HardwareService] connect error: $e');
      _connecting = false;
      _setStatus(const HwStatus.disconnected());
      if (!_disposed) _scheduleRetry();
    });

    socket.onReconnect((attempt) {
      debugPrint('[HardwareService] reconnect attempt: $attempt');
    });

    socket.onReconnectError((e) {
      debugPrint('[HardwareService] reconnect error: $e');
    });

    socket.on('hw_info', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final info = HwInfo.fromJson(map);
        _setStatus(HwStatus(
          status: HwConnectionStatus.hardwareReady,
          info: info,
          latencyMs: status.value.latencyMs,
        ));
        debugPrint('[HardwareService] hw_info: ${info.device} v${info.version}');
      } catch (e) {
        debugPrint('[HardwareService] hw_info parse error: $e');
      }
    });

    socket.on('frame', (data) {
      try {
        final Uint8List bytes;
        if (data is List<int>) {
          bytes = Uint8List.fromList(data);
        } else if (data is Uint8List) {
          bytes = data;
        } else {
          return;
        }
        onFrame?.call(bytes);
      } catch (e) {
        debugPrint('[HardwareService] frame parse error: $e');
      }
    });

    socket.on('audio', (data) {
      try {
        final Uint8List bytes;
        if (data is List<int>) {
          bytes = Uint8List.fromList(data);
        } else if (data is Uint8List) {
          bytes = data;
        } else {
          return;
        }
        onAudio?.call(bytes);
      } catch (e) {
        debugPrint('[HardwareService] audio parse error: $e');
      }
    });

    socket.on('pong_hw', (_) {
      if (_pingTimestamp > 0) {
        final latency = DateTime.now().millisecondsSinceEpoch - _pingTimestamp;
        _pingTimestamp = 0;
        _setStatus(HwStatus(
          status: status.value.status,
          info: status.value.info,
          latencyMs: latency,
        ));
      }
    });
  }

  /// Exponential backoff retry — doubles delay each failure, caps at 30s.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    debugPrint('[HardwareService] retry in ${_retryDelay.inSeconds}s');
    _retryTimer = Timer(_retryDelay, () async {
      if (_disposed) return;
      final retryResults = await Connectivity().checkConnectivity();
      if (_hasWifi(retryResults)) _tryConnect();
    });
    // Double the delay for next failure
    final next = Duration(seconds: _retryDelay.inSeconds * 2);
    _retryDelay = next > _maxRetryDelay ? _maxRetryDelay : next;
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(AppConfig.hwPingInterval, (_) {
      if (_socket?.connected == true) {
        _pingTimestamp = DateTime.now().millisecondsSinceEpoch;
        _socket!.emit('ping_hw');
      }
    });
  }

  void _cancelSocket() {
    _pingTimer?.cancel();
    _socket?.dispose();
    _socket = null;
    _connecting = false;
  }

  void _setStatus(HwStatus s) {
    if (!_disposed) status.value = s;
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  void startStream() => _emit('start_stream', {
        'fps': AppConfig.hwStreamFps,
        'quality': AppConfig.hwStreamQuality,
      });

  void stopStream() => _emit('stop_stream', {});

  void startMic() => _emit('start_mic', {});

  void stopMic() => _emit('stop_mic', {});

  void updateScreen({String top = '', String mid = '', String bot = ''}) =>
      _emit('update_screen', {'top': top, 'mid': mid, 'bot': bot});

  void speak(String text) => _emit('speak', {'text': text});

  void _emit(String event, dynamic data) {
    if (_socket?.connected == true) {
      _socket!.emit(event, data);
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    _cancelSocket();
    status.dispose();
  }
}
