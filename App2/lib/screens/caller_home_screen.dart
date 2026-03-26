import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/webrtc_provider.dart';
import '../screens/webrtc_call_screen.dart';

/// Home screen for Normal Person (caller-only) role.
/// Shows online deaf users and lets the user initiate audio/video calls.
/// Navigates to WebRtcCallScreen when a call becomes active.
class CallerHomeScreen extends StatefulWidget {
  const CallerHomeScreen({super.key});

  @override
  State<CallerHomeScreen> createState() => _CallerHomeScreenState();
}

class _CallerHomeScreenState extends State<CallerHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebRtcProvider>().addListener(_onWebRtcChanged);
    });
  }

  @override
  void dispose() {
    context.read<WebRtcProvider>().removeListener(_onWebRtcChanged);
    super.dispose();
  }

  void _onWebRtcChanged() {
    final webRtc = context.read<WebRtcProvider>();

    // Navigate to call screen when call becomes active
    if (webRtc.status == WebRtcCallStatus.active) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WebRtcCallScreen()),
      );
    }

    // Show incoming call dialog when someone calls us
    if (webRtc.status == WebRtcCallStatus.ringing) {
      _showIncomingCallDialog(webRtc);
    }
  }

  void _showIncomingCallDialog(WebRtcProvider webRtc) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.call_received, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('Incoming Call', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          '${webRtc.callerUsername ?? 'Someone'} is calling you…',
          style: const TextStyle(color: Color(0xFF9CA3AF)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              webRtc.rejectCall();
              Navigator.of(context).pop();
            },
            child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
            onPressed: () {
              Navigator.of(context).pop();
              webRtc.acceptCall();
            },
            child: const Text('Accept', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _callUser(WebRtcProvider webRtc, String targetUsername, String callType) async {
    webRtc.initiateCall(targetUsername, callType: callType);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, _) {
        final deafUsers = webRtc.onlineUsers
            .where((u) => u['role'] == 'deaf' && u['status'] != 'in_call')
            .toList();
        final allDeaf = webRtc.onlineUsers.where((u) => u['role'] == 'deaf').toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0D0D1A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF111127),
            title: const Text(
              'SYNAPSE',
              style: TextStyle(
                color: Color(0xFF06B6D4),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            actions: [
              // Connection indicator
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: webRtc.isConnected ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      webRtc.isConnected ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: webRtc.isConnected ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Status bar
              Container(
                width: double.infinity,
                color: const Color(0xFF111127),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${allDeaf.length} deaf user${allDeaf.length == 1 ? '' : 's'} registered'
                  ' · ${deafUsers.length} available',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ),

              // User list
              Expanded(
                child: allDeaf.isEmpty
                    ? _buildEmptyState(webRtc.isConnected)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: allDeaf.length,
                        itemBuilder: (context, i) {
                          final user = allDeaf[i];
                          final isInCall = user['status'] == 'in_call';
                          return _UserTile(
                            username: user['username'] as String,
                            isInCall: isInCall,
                            onAudioCall: isInCall
                                ? null
                                : () => _callUser(webRtc, user['username'] as String, 'audio'),
                            onVideoCall: isInCall
                                ? null
                                : () => _callUser(webRtc, user['username'] as String, 'video'),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isConnected) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.people_outline : Icons.wifi_off,
            size: 64,
            color: const Color(0xFF374151),
          ),
          const SizedBox(height: 16),
          Text(
            isConnected ? 'No deaf users online yet' : 'Connecting to server…',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String username;
  final bool isInCall;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;

  const _UserTile({
    required this.username,
    required this.isInCall,
    this.onAudioCall,
    this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInCall
              ? Colors.orangeAccent.withValues(alpha: 0.3)
              : const Color(0xFF06B6D4).withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF06B6D4).withValues(alpha: 0.15),
          child: Text(
            username[0].toUpperCase(),
            style: const TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          username,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          isInCall ? 'In a call' : 'Available',
          style: TextStyle(
            color: isInCall ? Colors.orangeAccent : Colors.greenAccent,
            fontSize: 12,
          ),
        ),
        trailing: isInCall
            ? const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.phone_in_talk, color: Colors.orangeAccent, size: 20),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Audio call
                  IconButton(
                    onPressed: onAudioCall,
                    icon: const Icon(Icons.call, color: Colors.greenAccent),
                    tooltip: 'Audio call',
                  ),
                  // Video call
                  IconButton(
                    onPressed: onVideoCall,
                    icon: const Icon(Icons.videocam, color: Color(0xFF06B6D4)),
                    tooltip: 'Video call',
                  ),
                ],
              ),
      ),
    );
  }
}
