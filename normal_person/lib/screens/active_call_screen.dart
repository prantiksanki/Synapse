import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../providers/call_provider.dart';
import '../models/webrtc_call_state.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _micOn = true;
  bool _camOn = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (provider.state.status == CallStatus.idle ||
              provider.state.status == CallStatus.ended) {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
        });

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Remote video — full screen background
              RTCVideoView(
                provider.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                placeholderBuilder: (_) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: const Center(
                    child: Icon(Icons.person, size: 80, color: Colors.grey),
                  ),
                ),
              ),

              // Local video — picture-in-picture top-right
              Positioned(
                top: 48,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 100,
                    height: 140,
                    child: RTCVideoView(
                      provider.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      placeholderBuilder: (_) => Container(color: Colors.black54),
                    ),
                  ),
                ),
              ),

              // Top info bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.state.remoteUsername ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 4)],
                              ),
                            ),
                            const Text(
                              'Connected',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withAlpha(200), Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mic toggle
                        _ControlButton(
                          icon: _micOn ? Icons.mic : Icons.mic_off,
                          label: _micOn ? 'Mute' : 'Unmute',
                          color: _micOn ? Colors.white : Colors.red,
                          onTap: () {
                            setState(() => _micOn = !_micOn);
                            provider.toggleMic();
                          },
                        ),
                        // End call
                        _ControlButton(
                          icon: Icons.call_end,
                          label: 'End',
                          color: Colors.white,
                          backgroundColor: Colors.red,
                          size: 64,
                          onTap: () {
                            provider.endCall();
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          },
                        ),
                        // Camera toggle
                        _ControlButton(
                          icon: _camOn ? Icons.videocam : Icons.videocam_off,
                          label: _camOn ? 'Cam off' : 'Cam on',
                          color: _camOn ? Colors.white : Colors.red,
                          onTap: () {
                            setState(() => _camOn = !_camOn);
                            provider.toggleCamera();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.backgroundColor = Colors.white24,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
