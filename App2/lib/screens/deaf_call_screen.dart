import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../providers/webrtc_provider.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/webrtc_call_screen.dart';

/// Dedicated calling page for deaf users.
/// Shows online hearing (caller) users and lets the deaf user initiate calls.
class DeafCallScreen extends StatefulWidget {
  const DeafCallScreen({super.key});

  @override
  State<DeafCallScreen> createState() => _DeafCallScreenState();
}

class _DeafCallScreenState extends State<DeafCallScreen>
    with SingleTickerProviderStateMixin {
  bool _incomingRouteOpen = false;
  bool _callRouteOpen = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-register with the signaling server each time this screen opens.
      // DetectionScreen connects on app launch, but the socket may have
      // dropped or the user may have navigated away — reconnect to be safe.
      context.read<WebRtcProvider>().connectFromPrefs();
      _showFirstOpenAlert();
    });
  }

  Future<void> _showFirstOpenAlert() async {
    final prefs = await SharedPreferences.getInstance();
    const seenKey = 'deaf_call_page_alert_seen';
    final hasSeenAlert = prefs.getBool(seenKey) ?? false;

    if (hasSeenAlert || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Before you start'),
          content: const Text(
            'This page helps deaf users call available people. Choose a person '
            'who is online, then start an audio or video call.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    await prefs.setBool(seenKey, true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _handleWebRtcChange(WebRtcProvider webRtc) {
    // Control pulse animation: only animate while ringing
    if (webRtc.status == WebRtcCallStatus.ringing) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      if (_pulseCtrl.isAnimating) {
        _pulseCtrl.stop();
        _pulseCtrl.value = 1.0;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (webRtc.status == WebRtcCallStatus.ringing &&
          !_incomingRouteOpen &&
          !_callRouteOpen) {
        _incomingRouteOpen = true;
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const IncomingCallScreen()))
            .whenComplete(() {
          if (mounted) _incomingRouteOpen = false;
        });
        return;
      }

      if (webRtc.status == WebRtcCallStatus.active && !_callRouteOpen) {
        _callRouteOpen = true;
        if (_incomingRouteOpen) {
          Navigator.of(context).pop();
          _incomingRouteOpen = false;
        }
        Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => const WebRtcCallScreen()))
            .whenComplete(() {
          if (mounted) _callRouteOpen = false;
        });
        return;
      }

      if (webRtc.status == WebRtcCallStatus.idle ||
          webRtc.status == WebRtcCallStatus.ended) {
        _incomingRouteOpen = false;
        _callRouteOpen = false;
      }
    });
  }

  void _initiateCall(WebRtcProvider webRtc, String target, String callType) {
    webRtc.initiateCall(target, callType: callType);
  }

  // ─── build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, _) {
        _handleWebRtcChange(webRtc);

        // Only show users with the 'caller' role — deaf-to-deaf calls
        // don't make sense and clutter the list.
        final callers = webRtc.onlineUsers
            .where((u) =>
                u['username'] != webRtc.myUsername &&
                u['role'] == 'caller')
            .toList();
        final available = callers
            .where((u) => u['status'] != 'in_call')
            .toList();

        return Scaffold(
          backgroundColor: AppConfig.obBackground,
          appBar: AppBar(
            backgroundColor: AppConfig.obBackground,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppConfig.obPrimaryDark, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Call',
              style: TextStyle(
                color: AppConfig.obTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 9,
                      color: webRtc.isConnected
                          ? const Color(0xFF34D399)
                          : Colors.redAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      webRtc.isConnected ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: webRtc.isConnected
                            ? const Color(0xFF34D399)
                            : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status bar ──────────────────────────────
              _StatusBar(
                total: callers.length,
                available: available.length,
                status: webRtc.status,
                pulse: _pulseAnim,
              ),

              // ── User list ───────────────────────────────
              Expanded(
                child: callers.isEmpty
                    ? _EmptyState(isConnected: webRtc.isConnected)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: callers.length,
                        itemBuilder: (context, i) {
                          final user = callers[i];
                          final username =
                              user['username'] as String;
                          final isInCall =
                              user['status'] == 'in_call';
                          return _CallerTile(
                            username: username,
                            isInCall: isInCall,
                            onAudioCall: isInCall
                                ? null
                                : () => _initiateCall(
                                    webRtc, username, 'audio'),
                            onVideoCall: isInCall
                                ? null
                                : () => _initiateCall(
                                    webRtc, username, 'video'),
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
}

// ─────────────────────────────────────────────────────────────
//  Status bar
// ─────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final int total;
  final int available;
  final WebRtcCallStatus status;
  final Animation<double> pulse;

  const _StatusBar({
    required this.total,
    required this.available,
    required this.status,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    // Active call banner
    if (status == WebRtcCallStatus.active ||
        status == WebRtcCallStatus.ringing) {
      final isRinging = status == WebRtcCallStatus.ringing;
      return ScaleTransition(
        scale: isRinging ? pulse : const AlwaysStoppedAnimation(1.0),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isRinging
                ? const Color(0xFFFFF3CD)
                : const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRinging
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF34D399),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isRinging ? Icons.ring_volume_outlined : Icons.phone_in_talk,
                color: isRinging
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF34D399),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                isRinging ? 'Incoming call...' : 'Call in progress',
                style: TextStyle(
                  color: isRinging
                      ? const Color(0xFF92400E)
                      : const Color(0xFF065F46),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal summary bar
    return Container(
      width: double.infinity,
      color: AppConfig.obBackground,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Text(
        '$total user${total == 1 ? '' : 's'} online'
        ' · $available available',
        style: const TextStyle(
            color: AppConfig.obTextSecondary, fontSize: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Caller tile
// ─────────────────────────────────────────────────────────────

class _CallerTile extends StatelessWidget {
  final String username;
  final bool isInCall;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;

  const _CallerTile({
    required this.username,
    required this.isInCall,
    this.onAudioCall,
    this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isInCall
              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
              : AppConfig.obBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppConfig.obPrimary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
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
                color: AppConfig.obPrimary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  username[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppConfig.obPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
                      fontWeight: FontWeight.w600,
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
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF34D399),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isInCall ? 'In a call' : 'Available',
                        style: TextStyle(
                          color: isInCall
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF34D399),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Call buttons
            if (isInCall)
              const Icon(Icons.phone_in_talk,
                  color: Color(0xFFF59E0B), size: 22)
            else
              Row(
                children: [
                  _CallButton(
                    icon: Icons.call_rounded,
                    color: const Color(0xFF34D399),
                    tooltip: 'Audio call',
                    onTap: onAudioCall,
                  ),
                  const SizedBox(width: 10),
                  _CallButton(
                    icon: Icons.videocam_rounded,
                    color: AppConfig.obAccentBlue,
                    tooltip: 'Video call',
                    onTap: onVideoCall,
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
  final String tooltip;
  final VoidCallback? onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: color.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────

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
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppConfig.obBorder,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnected ? Icons.people_outline_rounded : Icons.wifi_off_rounded,
              size: 44,
              color: AppConfig.obPrimary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isConnected
                ? 'No hearing users online'
                : 'Connecting to server…',
            style: const TextStyle(
              color: AppConfig.obTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnected
                ? 'Hearing users will appear here\nwhen they come online.'
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
