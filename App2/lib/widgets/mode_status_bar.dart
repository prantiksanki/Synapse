import 'package:flutter/material.dart';
import '../providers/detection_provider.dart';

/// A persistent pill-shaped bar showing which mode is currently dominant.
///
/// Three chips: Sign (cyan) | Voice (lightBlue, pulsing) | Call (green)
class ModeStatusBar extends StatelessWidget {
  const ModeStatusBar({
    super.key,
    required this.dominantMode,
    required this.sttIsListening,
    required this.callIsActive,
    required this.isTtsSpeaking,
    this.callerNumber = '',
  });

  final AppMode dominantMode;
  final bool sttIsListening;
  final bool callIsActive;
  final bool isTtsSpeaking;
  final String callerNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ModeChip(
              label: 'Sign',
              icon: Icons.sign_language,
              activeColor: const Color(0xFF8B5CF6),
              isActive: dominantMode == AppMode.gestureMode,
            ),
            _divider(),
            _ModeChip(
              label: 'Voice',
              icon: Icons.mic,
              activeColor: const Color(0xFF60A5FA),
              isActive: dominantMode == AppMode.speechMode,
              isPulsing: sttIsListening,
            ),
            _divider(),
            _ModeChip(
              label: 'Call',
              icon: Icons.call,
              activeColor: const Color(0xFF34D399),
              isActive: callIsActive,
              isTtsSpeaking: isTtsSpeaking,
              callerNumber: callerNumber,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        color: const Color(0xFFF3F4F6),
      );
}

class _ModeChip extends StatefulWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.isActive,
    this.isPulsing = false,
    this.isTtsSpeaking = false,
    this.callerNumber = '',
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final bool isActive;
  final bool isPulsing;
  final bool isTtsSpeaking;
  final String callerNumber;

  @override
  State<_ModeChip> createState() => _ModeChipState();
}

class _ModeChipState extends State<_ModeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_pulse);
    if (widget.isPulsing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ModeChip old) {
    super.didUpdateWidget(old);
    if (widget.isPulsing && !old.isPulsing) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isPulsing && old.isPulsing) {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? widget.activeColor : const Color(0xFF9CA3AF);
    final bg = widget.isActive ? widget.activeColor.withValues(alpha: 0.15) : Colors.transparent;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: widget.isActive
              ? Border.all(color: widget.activeColor.withValues(alpha: 0.5), width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: widget.isPulsing ? _opacity : const AlwaysStoppedAnimation(1.0),
                  child: Icon(widget.icon, color: color, size: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (widget.isTtsSpeaking) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.volume_up, color: color, size: 10),
                ],
              ],
            ),
            if (widget.callerNumber.isNotEmpty)
              Text(
                widget.callerNumber,
                style: TextStyle(color: color, fontSize: 9),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
