import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/webrtc_provider.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/webrtc_call_screen.dart';

/// Home screen for Normal Person (caller-only) role.
/// Single screen — no navbar. Shows online deaf users and lets the user call.
class CallerHomeScreen extends StatefulWidget {
  const CallerHomeScreen({super.key});

  @override
  State<CallerHomeScreen> createState() => _CallerHomeScreenState();
}

class _CallerHomeScreenState extends State<CallerHomeScreen> {
  bool _incomingRouteOpen = false;
  bool _callRouteOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final webRtc = context.read<WebRtcProvider>();
      webRtc.addListener(_onWebRtcChanged);
      webRtc.connectFromPrefs();
    });
  }

  @override
  void dispose() {
    context.read<WebRtcProvider>().removeListener(_onWebRtcChanged);
    super.dispose();
  }

  void _onWebRtcChanged() {
    if (!mounted) return;
    final webRtc = context.read<WebRtcProvider>();

    if (webRtc.status == WebRtcCallStatus.ringing &&
        !_incomingRouteOpen &&
        !_callRouteOpen) {
      if (webRtc.userRole != 'caller' || webRtc.callerUsername == null) {
        _incomingRouteOpen = true;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const IncomingCallScreen()))
            .whenComplete(() => _incomingRouteOpen = false);
        return;
      }
    }

    if (webRtc.status == WebRtcCallStatus.active && !_callRouteOpen) {
      _callRouteOpen = true;
      if (_incomingRouteOpen) {
        Navigator.of(context).pop();
        _incomingRouteOpen = false;
      }
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const WebRtcCallScreen()))
          .whenComplete(() => _callRouteOpen = false);
      return;
    }

    if (webRtc.status == WebRtcCallStatus.idle ||
        webRtc.status == WebRtcCallStatus.ended) {
      _incomingRouteOpen = false;
      _callRouteOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, _) {
        // Only show users with the 'deaf' role — caller-to-caller calls
        // don't make sense and clutter the list.
        final allUsers = webRtc.onlineUsers
            .where((u) =>
                u['username'] != webRtc.myUsername &&
                u['role'] == 'deaf')
            .toList();
        final availableUsers =
            allUsers.where((u) => u['status'] != 'in_call').toList();

        return Scaffold(
          backgroundColor: AppConfig.obBackground,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────
                _Header(webRtc: webRtc),

                // ── Stats bar ────────────────────────────────────────
                if (allUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '${allUsers.length} user${allUsers.length == 1 ? '' : 's'} online'
                      ' · ${availableUsers.length} available',
                      style: const TextStyle(
                        color: AppConfig.obTextSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // ── User list / empty state ───────────────────────────
                Expanded(
                  child: allUsers.isEmpty
                      ? _EmptyState(isConnected: webRtc.isConnected)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: allUsers.length,
                          itemBuilder: (context, i) {
                            final user = allUsers[i];
                            final isInCall = user['status'] == 'in_call';
                            return _UserTile(
                              username: user['username'] as String,
                              isInCall: isInCall,
                              onAudioCall: isInCall
                                  ? null
                                  : () => webRtc.initiateCall(
                                        user['username'] as String,
                                        callType: 'audio',
                                      ),
                              onVideoCall: isInCall
                                  ? null
                                  : () => webRtc.initiateCall(
                                        user['username'] as String,
                                        callType: 'video',
                                      ),
                            );
                          },
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

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final WebRtcProvider webRtc;
  const _Header({required this.webRtc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VAANI',
                  style: TextStyle(
                    color: AppConfig.obTextPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sign Language Calling',
                  style: TextStyle(
                    color: AppConfig.obTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Connection badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppConfig.obCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppConfig.obBorder, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: webRtc.isConnected
                        ? const Color(0xFF22C55E)
                        : Colors.redAccent,
                    boxShadow: [
                      BoxShadow(
                        color: (webRtc.isConnected
                                ? const Color(0xFF22C55E)
                                : Colors.redAccent)
                            .withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  webRtc.isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: webRtc.isConnected
                        ? const Color(0xFF22C55E)
                        : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── User tile ─────────────────────────────────────────────────────────────────

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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInCall
              ? Colors.orangeAccent.withValues(alpha: 0.3)
              : AppConfig.obBorder,
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.obPrimary.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppConfig.obPrimary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  username[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppConfig.obPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: AppConfig.obTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isInCall
                              ? Colors.orangeAccent
                              : const Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isInCall ? 'In a call' : 'Available',
                        style: TextStyle(
                          color: isInCall
                              ? Colors.orangeAccent
                              : const Color(0xFF22C55E),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Call buttons
            if (isInCall)
              const Icon(
                Icons.phone_in_talk_rounded,
                color: Colors.orangeAccent,
                size: 22,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CallButton(
                    icon: Icons.call_rounded,
                    color: const Color(0xFF22C55E),
                    onTap: onAudioCall,
                    tooltip: 'Audio call',
                  ),
                  const SizedBox(width: 8),
                  _CallButton(
                    icon: Icons.videocam_rounded,
                    color: AppConfig.obPrimary,
                    onTap: onVideoCall,
                    tooltip: 'Video call',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isConnected;
  const _EmptyState({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConfig.obCard,
              border: Border.all(color: AppConfig.obBorder, width: 1.5),
            ),
            child: Icon(
              isConnected ? Icons.people_outline_rounded : Icons.wifi_off_rounded,
              size: 36,
              color: AppConfig.obTextSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isConnected ? 'No users online yet' : 'Connecting to server…',
            style: const TextStyle(
              color: AppConfig.obTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? 'Deaf users will appear here\nwhen they come online.'
                : 'Please check your internet connection.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppConfig.obTextSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
