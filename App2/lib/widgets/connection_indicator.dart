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
        'Hardware ready: ${status.info?.device ?? "SYNAPSE-HW"}',
        const Color(0xFF34D399),
      );
    }
    // disconnected / connecting / connected all show as OFF
    return (Icons.wifi_off, 'SYNAPSE hardware not connected', const Color(0xFFEF4444));
  }

  String _shortLabel() {
    return status.status == HwConnectionStatus.hardwareReady ? 'HW ON' : 'HW OFF';
  }
}
