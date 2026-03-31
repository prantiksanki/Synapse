import 'hw_info.dart';

enum HwConnectionStatus { disconnected, connecting, connected, hardwareReady }

class HwStatus {
  final HwConnectionStatus status;
  final HwInfo? info;
  final int? latencyMs;
  final String? error;

  const HwStatus({
    required this.status,
    this.info,
    this.latencyMs,
    this.error,
  });

  const HwStatus.disconnected()
      : status = HwConnectionStatus.disconnected,
        info = null,
        latencyMs = null,
        error = null;

  bool get isConnected =>
      status == HwConnectionStatus.connected ||
      status == HwConnectionStatus.hardwareReady;

  bool get isReady => status == HwConnectionStatus.hardwareReady;
}
