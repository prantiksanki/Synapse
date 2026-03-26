import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../models/webrtc_call_state.dart';
import 'active_call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (provider.state.status == CallStatus.active) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
            );
          } else if (provider.state.status == CallStatus.idle ||
              provider.state.status == CallStatus.ended) {
            Navigator.pop(context);
          }
        });

        final name = provider.state.remoteUsername ?? '';
        final isVideo = provider.state.callType == 'video';

        return Scaffold(
          backgroundColor: const Color(0xFF0D1117),
          body: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                // Avatar
                CircleAvatar(
                  radius: 56,
                  backgroundColor: const Color(0xFF00BCD4),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 48,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Incoming ${isVideo ? 'video' : 'audio'} call…',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
                const Spacer(),
                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Reject
                      Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'reject',
                            onPressed: () {
                              provider.rejectCall();
                              Navigator.pop(context);
                            },
                            backgroundColor: Colors.red,
                            child: const Icon(Icons.call_end, size: 28),
                          ),
                          const SizedBox(height: 8),
                          const Text('Decline', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                      // Accept
                      Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'accept',
                            onPressed: provider.acceptCall,
                            backgroundColor: Colors.green,
                            child: Icon(
                              isVideo ? Icons.videocam : Icons.call,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Accept', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
