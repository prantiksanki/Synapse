import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../models/webrtc_call_state.dart';
import 'incoming_call_screen.dart';
import 'active_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, _) {
        // React to call state changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final status = provider.state.status;
          if (status == CallStatus.ringing) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IncomingCallScreen()),
            );
          } else if (status == CallStatus.active) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
              (r) => r.isFirst,
            );
          }
        });

        final deafUsers = provider.onlineUsers
            .where((u) => u['role'] == 'deaf')
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Hi, ${provider.username ?? ''}'),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Chip(
                  label: Text(
                    '${deafUsers.length} online',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: const Color(0xFF00BCD4).withAlpha(40),
                  side: const BorderSide(color: Color(0xFF00BCD4), width: 1),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Error banner
              if (provider.errorMessage != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    provider.errorMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              // Calling banner
              if (provider.state.status == CallStatus.calling)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF00BCD4).withAlpha(30),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00BCD4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Calling ${provider.state.remoteUsername}…',
                      style: const TextStyle(color: Color(0xFF00BCD4)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: provider.endCall,
                      child: const Icon(Icons.call_end, color: Colors.red, size: 20),
                    ),
                  ]),
                ),
              // User list
              Expanded(
                child: deafUsers.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: deafUsers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                        itemBuilder: (_, i) => _UserTile(
                          user: deafUsers[i],
                          onAudioCall: () => provider.callUser(
                            deafUsers[i]['username'] as String,
                            video: false,
                          ),
                          onVideoCall: () => provider.callUser(
                            deafUsers[i]['username'] as String,
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

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No deaf users online', style: TextStyle(color: Colors.grey, fontSize: 16)),
          SizedBox(height: 8),
          Text('They will appear here when connected', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;

  const _UserTile({
    required this.user,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String;
    final inCall = user['status'] == 'in_call';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: inCall ? Colors.orange.shade900 : const Color(0xFF00BCD4),
        child: Text(
          username[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(username),
      subtitle: Text(
        inCall ? 'In a call' : 'Available',
        style: TextStyle(
          color: inCall ? Colors.orange : Colors.green,
          fontSize: 12,
        ),
      ),
      trailing: inCall
          ? const Icon(Icons.phone_in_talk, color: Colors.orange, size: 20)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: onAudioCall,
                  tooltip: 'Audio call',
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Color(0xFF00BCD4)),
                  onPressed: onVideoCall,
                  tooltip: 'Video call',
                ),
              ],
            ),
    );
  }
}
