import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_bridge_provider.dart';
import '../services/call_bridge_service.dart';
import '../screens/call_overlay_screen.dart';

/// Thin animated banner shown at the top of [DetectionScreen] whenever a
/// phone call is ringing or active.  Tapping it opens [CallOverlayScreen].
class CallStatusBanner extends StatelessWidget {
  const CallStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallBridgeProvider>(
      builder: (context, provider, _) {
        final state = provider.callState;
        if (state == PhoneCallState.idle) return const SizedBox.shrink();

        final isRinging = state == PhoneCallState.ringing;
        final label = isRinging
            ? 'Incoming call${provider.callerNumber.isNotEmpty ? ': ${provider.callerNumber}' : ''}'
            : 'Call active — sign to speak';

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CallOverlayScreen()),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: isRinging
                ? const Color(0xFFF59E0B).withValues(alpha: 0.92)
                : const Color(0xFF34D399).withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _PulsingDot(color: isRinging ? Colors.white : Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}
