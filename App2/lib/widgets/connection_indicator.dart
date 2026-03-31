import 'package:flutter/material.dart';
import '../models/connection_state.dart';

/// A compact status badge shown in the AppBar to indicate Pi hardware connection.
class ConnectionIndicator extends StatelessWidget {
  final HwStatus status;

  const ConnectionIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _badge();
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                _shortLabel(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status.latencyMs != null) ...[
                const SizedBox(width: 4),
                Text(
                  '${status.latencyMs}ms',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String, Color) _badge() {
    if (status.status == HwConnectionStatus.hardwareReady) {
      return (
        Icons.hardware,
        'Hardware ready: ${status.info?.device ?? "VAANI-HW"}',
        const Color(0xFF34D399),
      );
    }
    if (status.status == HwConnectionStatus.connecting) {
      return (
        Icons.wifi_find,
        'Connecting to VAANI hardware...',
        const Color(0xFFF59E0B),
      );
    }
    if (status.status == HwConnectionStatus.connected) {
      return (
        Icons.sync,
        'Connected to hardware socket, waiting for device info...',
        const Color(0xFF60A5FA),
      );
    }
    final message = status.error == null || status.error!.isEmpty
        ? 'VAANI hardware not connected'
        : 'VAANI hardware not connected: ${status.error}';
    return (Icons.wifi_off, message, const Color(0xFFEF4444));
  }

  String _shortLabel() {
    return switch (status.status) {
      HwConnectionStatus.hardwareReady => 'HW ON',
      HwConnectionStatus.connecting => 'HW...',
      HwConnectionStatus.connected => 'HW SYNC',
      HwConnectionStatus.disconnected => 'HW OFF',
    };
  }
}

