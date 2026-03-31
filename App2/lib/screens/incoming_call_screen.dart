import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/webrtc_provider.dart';
import 'webrtc_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WebRtcProvider>().addListener(_onWebRtcChanged);
    });
  }

  @override
  void dispose() {
    context.read<WebRtcProvider>().removeListener(_onWebRtcChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onWebRtcChanged() {
    if (!mounted) return;
    final webRtc = context.read<WebRtcProvider>();
    if (webRtc.status == WebRtcCallStatus.active) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WebRtcCallScreen()),
      );
      return;
    }
    if (webRtc.status == WebRtcCallStatus.idle ||
        webRtc.status == WebRtcCallStatus.ended) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, _) {
        final name = webRtc.callerUsername ?? 'Unknown';
        final isVideo = webRtc.pendingCallType == 'video';

        return Scaffold(
          backgroundColor: const Color(0xFF0B141A),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  const Spacer(),
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_pulse),
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1F2C34),
                        border: Border.all(color: const Color(0xFF25D366), width: 3),
                      ),
                      child: Center(
                        child: Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isVideo ? 'Incoming video call…' : 'Incoming audio call…',
                    style: const TextStyle(color: Color(0xFFAEBAC1), fontSize: 16),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        color: const Color(0xFFE0245E),
                        icon: Icons.call_end,
                        label: 'Decline',
                        onTap: () => webRtc.rejectCall(),
                      ),
                      _CallActionButton(
                        color: const Color(0xFF25D366),
                        icon: isVideo ? Icons.videocam : Icons.call,
                        label: _accepting ? 'Connecting…' : 'Accept',
                        onTap: _accepting
                            ? null
                            : () async {
                                setState(() => _accepting = true);
                                await webRtc.acceptCall();
                                if (mounted) setState(() => _accepting = false);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    );
  }
}
