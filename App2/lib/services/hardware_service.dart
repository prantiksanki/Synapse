import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../config/app_config.dart';
import '../models/connection_state.dart';
import '../models/hw_info.dart';

/// Ultra-low-latency hardware service.
///
/// Video  → raw MJPEG over HTTP  (no Socket.IO overhead per frame)
/// Audio  → Socket.IO binary     (tight 16 ms chunks)
/// Control→ Socket.IO events
class HardwareService {
  static HardwareService? _instance;

  factory HardwareService() {
    _instance ??= HardwareService._internal();
    return _instance!;
  }

  HardwareService._internal();

  // ── Socket.IO (control + audio) ──────────────────────────────────────────
  socket_io.Socket? _socket;
  Timer? _retryTimer;
  Timer? _connectTimer;
  Timer? _pingTimer;
  int _pingTimestamp = 0;
  Duration _retryDelay = const Duration(seconds: 3);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  // ── MJPEG (video) ─────────────────────────────────────────────────────────
  http.Client? _mjpegClient;
  StreamSubscription<List<int>>? _mjpegSub;
  String? _mjpegUrl;                    // filled from hw_info handshake
  final _mjpegBuffer = <int>[];
  bool _mjpegRunning = false;

  // ── Connectivity ──────────────────────────────────────────────────────────
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ── Public state ──────────────────────────────────────────────────────────
  final ValueNotifier<HwStatus> status =
      ValueNotifier(const HwStatus.disconnected());

  void Function(Uint8List jpeg)? onFrame;
  void Function(Uint8List pcm)? onAudio;

  bool _disposed = false;
  bool _connecting = false;
  bool _micRequested = false;

  // ── MJPEG boundary markers ─────────────────────────────────────────────────
  static const List<int> _boundaryBytes = [0xFF, 0xD8];   // JPEG SOI
  static const List<int> _eoi           = [0xFF, 0xD9];   // JPEG EOI

  // =========================================================================
  // Connection lifecycle
  // =========================================================================

  Future<void> connect() async {
    if (_disposed || _connecting || _socket?.connected == true) return;

    _connectivitySub ??=
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    final results = await Connectivity().checkConnectivity();
    if (_hasWifi(results)) {
      await _tryConnect();
    } else {
      _setStatus(const HwStatus.disconnected());
    }
  }

  bool _hasWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;

    if (_hasWifi(results)) {
      _connectTimer?.cancel();
      _retryDelay = const Duration(seconds: 3);
      _connectTimer = Timer(const Duration(seconds: 1), () {
        if (!_disposed && !_connecting && _socket?.connected != true) {
          _tryConnect();
        }
      });
    } else {
      _cancelSocket();
      _stopMjpeg();
      _connectTimer?.cancel();
      _setStatus(const HwStatus.disconnected());
    }
  }

  Future<void> _tryConnect() async {
    if (_disposed || _connecting || _socket?.connected == true) return;

    _connecting = true;
    _setStatus(HwStatus(
      status: HwConnectionStatus.connecting,
      info: status.value.info,
      latencyMs: status.value.latencyMs,
    ));

    try {
      await _cancelSocket();

      _socket = socket_io.io(
        AppConfig.hwSocketUrl,
        socket_io.OptionBuilder()
            .setTransports(['websocket'])
            .setPath('/socket.io/')
            .disableAutoConnect()
            .disableReconnection()
            .enableForceNew()
            .setTimeout(8000)
            .build(),
      );

      _setupListeners();
      _socket!.connect();
    } catch (e) {
      _connecting = false;
      _setStatus(HwStatus(
        status: HwConnectionStatus.disconnected,
        error: e.toString(),
      ));
      _scheduleRetry();
    }
  }

  // =========================================================================
  // Socket.IO listeners
  // =========================================================================

  void _setupListeners() {
    final socket = _socket!;
    socket.clearListeners();

    socket.onConnect((_) {
      _connecting = false;
      _retryDelay = const Duration(seconds: 3);
      _setStatus(HwStatus(
        status: HwConnectionStatus.connected,
        info: status.value.info,
        latencyMs: status.value.latencyMs,
      ));
      _startPingTimer();
    });

    socket.onDisconnect((_) {
      _connecting = false;
      _stopMjpeg();
      _resetRuntimeState();
      _setStatus(HwStatus(
        status: HwConnectionStatus.disconnected,
        error: 'Socket disconnected',
      ));
      if (!_disposed) _scheduleRetry();
    });

    socket.onConnectError((e) {
      _connecting = false;
      _setStatus(HwStatus(
        status: HwConnectionStatus.disconnected,
        error: e?.toString(),
      ));
      if (!_disposed) _scheduleRetry();
    });

    socket.onError((e) {
      _setStatus(HwStatus(
        status: status.value.status,
        info: status.value.info,
        latencyMs: status.value.latencyMs,
        error: e?.toString(),
      ));
    });

    socket.on('hw_info', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final info = HwInfo.fromJson(map);

        // Grab MJPEG URL sent by server in hw_info
        _mjpegUrl = map['mjpeg_url'] as String?;

        _setStatus(HwStatus(
          status: HwConnectionStatus.hardwareReady,
          info: info,
          latencyMs: status.value.latencyMs,
        ));

        _ensureHardwareStreams();
      } catch (_) {}
    });

    socket.on('hw_error', (data) {
      final message = data is Map
          ? (Map<String, dynamic>.from(data as Map))['message']?.toString()
          : data?.toString();
      _setStatus(HwStatus(
        status: status.value.status,
        info: status.value.info,
        latencyMs: status.value.latencyMs,
        error: message,
      ));
    });

    // Audio arrives via Socket.IO (video now MJPEG)
    socket.on('audio', (data) {
      try {
        final bytes = _decodeBytes(data);
        if (bytes == null) return;
        onAudio?.call(bytes);
      } catch (_) {}
    });

    socket.on('pong_hw', (_) {
      if (_pingTimestamp > 0) {
        final latency = DateTime.now().millisecondsSinceEpoch - _pingTimestamp;
        _pingTimestamp = 0;
        _setStatus(HwStatus(
          status: status.value.status,
          info: status.value.info,
          latencyMs: latency,
          error: status.value.error,
        ));
      }
    });
  }

  // =========================================================================
  // MJPEG video stream
  // =========================================================================

  Future<void> _startMjpeg() async {
    if (_mjpegRunning || _mjpegUrl == null) return;
    _mjpegRunning = true;
    _mjpegBuffer.clear();

    try {
      _mjpegClient = http.Client();
      final request = http.Request('GET', Uri.parse(_mjpegUrl!));
      request.headers['Connection'] = 'keep-alive';

      final response = await _mjpegClient!.send(request);

      _mjpegSub = response.stream.listen(
        _onMjpegChunk,
        onDone: () {
          _mjpegRunning = false;
          // Auto-reconnect video if still supposed to be running
          if (!_disposed && _socket?.connected == true) {
            Future.delayed(const Duration(milliseconds: 200), _startMjpeg);
          }
        },
        onError: (_) {
          _mjpegRunning = false;
          if (!_disposed && _socket?.connected == true) {
            Future.delayed(const Duration(milliseconds: 500), _startMjpeg);
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      _mjpegRunning = false;
      if (!_disposed && _socket?.connected == true) {
        Future.delayed(const Duration(milliseconds: 500), _startMjpeg);
      }
    }
  }

  /// Parse raw multipart MJPEG stream bytes into individual JPEG frames.
  /// Scans for SOI (0xFF 0xD8) … EOI (0xFF 0xD9) sequences.
  void _onMjpegChunk(List<int> chunk) {
    _mjpegBuffer.addAll(chunk);

    while (true) {
      // Find SOI
      final soi = _indexOf(_mjpegBuffer, _boundaryBytes);
      if (soi == -1) {
        // No SOI yet — keep at most the last byte (partial marker)
        if (_mjpegBuffer.length > 1) {
          final last = _mjpegBuffer.last;
          _mjpegBuffer.clear();
          _mjpegBuffer.add(last);
        }
        break;
      }

      // Find EOI after SOI
      final eoi = _indexOf(_mjpegBuffer, _eoi, start: soi + 2);
      if (eoi == -1) break; // frame not complete yet

      final frameEnd = eoi + 2;
      final jpeg = Uint8List.fromList(_mjpegBuffer.sublist(soi, frameEnd));
      _mjpegBuffer.removeRange(0, frameEnd);

      onFrame?.call(jpeg);
    }

    // Prevent unbounded growth (e.g., corrupt stream)
    if (_mjpegBuffer.length > 512 * 1024) {
      _mjpegBuffer.clear();
    }
  }

  int _indexOf(List<int> haystack, List<int> needle, {int start = 0}) {
    outer:
    for (int i = start; i <= haystack.length - needle.length; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void _stopMjpeg() {
    _mjpegRunning = false;
    _mjpegSub?.cancel();
    _mjpegSub = null;
    _mjpegClient?.close();
    _mjpegClient = null;
    _mjpegBuffer.clear();
  }

  // =========================================================================
  // Stream management
  // =========================================================================

  void _ensureHardwareStreams() {
    if (_socket?.connected != true) return;
    _startMjpeg();

    // Mic — uncomment once video is confirmed stable
    // if (!_micRequested) {
    //   _micRequested = true;
    //   startMic();
    // }
  }

  // =========================================================================
  // Retry / ping
  // =========================================================================

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () async {
      if (_disposed) return;
      final results = await Connectivity().checkConnectivity();
      if (_hasWifi(results)) _tryConnect();
    });
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

  // =========================================================================
  // Helpers
  // =========================================================================

  Future<void> _cancelSocket() async {
    _pingTimer?.cancel();
    if (_socket != null) {
      _socket!.clearListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _connecting = false;
  }

  void _resetRuntimeState() {
    _pingTimer?.cancel();
    _pingTimestamp = 0;
    _micRequested = false;
  }

  void _setStatus(HwStatus s) {
    if (!_disposed) status.value = s;
  }

  Uint8List? _decodeBytes(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) {
      return Uint8List.fromList(
        data.whereType<num>().map((v) => v.toInt()).toList(),
      );
    }
    return null;
  }

  // =========================================================================
  // Public API
  // =========================================================================

  void startMic() {
    _micRequested = true;
    _emit('start_mic', {});
  }

  void stopMic() {
    _micRequested = false;
    _emit('stop_mic', {});
  }

  void updateScreen({String top = '', String mid = '', String bot = ''}) =>
      _emit('update_screen', {'top': top, 'mid': mid, 'bot': bot});

  void speak(String text) => _emit('speak', {'text': text});

  /// Legacy: still emits to server but video is now via MJPEG.
  void startStream() => _emit('start_stream', {
        'fps': AppConfig.hwStreamFps,
        'quality': AppConfig.hwStreamQuality,
      });

  void stopStream() {
    _stopMjpeg();
    _emit('stop_stream', {});
  }

  void _emit(String event, dynamic data) {
    if (_socket?.connected == true) _socket!.emit(event, data);
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _connectTimer?.cancel();
    _connectivitySub?.cancel();
    _stopMjpeg();
    _cancelSocket();
    status.dispose();
  }
}
