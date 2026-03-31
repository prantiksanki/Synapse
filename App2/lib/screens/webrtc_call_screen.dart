import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../providers/webrtc_provider.dart';
import '../services/sign_image_service.dart';

class WebRtcCallScreen extends StatefulWidget {
  const WebRtcCallScreen({super.key});

  @override
  State<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends State<WebRtcCallScreen>
    with SingleTickerProviderStateMixin {
  bool _sheetExpanded = true;

  // Waveform runs at reduced rate (12 fps) via Ticker, not 60fps AnimationController.
  late final Ticker _waveTicker;
  double _waveProgress = 0;
  int _waveLastMs = 0;
  static const int _waveIntervalMs = 83; // ~12 fps

  // Performance monitor state
  int _frameCount = 0;
  double _displayFps = 0;
  int _lastFpsMs = 0;
  final List<int> _frameTimes = [];
  bool _perfVisible = false;

  @override
  void initState() {
    super.initState();

    // Waveform ticker — fires every vsync but we gate to ~12 fps internally.
    _waveTicker = createTicker(_onWaveTick)..start();

    // FPS ticker — separate, same gate.
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WebRtcProvider>().addListener(_onWebRtcChanged);
    });
  }

  void _onWaveTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms - _waveLastMs < _waveIntervalMs) return;
    _waveLastMs = ms;
    if (mounted) setState(() => _waveProgress = (ms % 1000) / 1000.0);
  }

  void _onFrame(Duration ts) {
    if (!mounted) return;
    final ms = ts.inMilliseconds;
    _frameTimes.add(ms);
    _frameCount++;
    if (ms - _lastFpsMs >= 1000) {
      // Keep only last 60 frame timestamps for render-time calculation.
      if (_frameTimes.length > 60) _frameTimes.removeRange(0, _frameTimes.length - 60);
      if (mounted) {
        setState(() {
          _displayFps = _frameCount.toDouble();
          _frameCount = 0;
          _lastFpsMs = ms;
        });
      } else {
        _frameCount = 0;
        _lastFpsMs = ms;
      }
    }
  }

  @override
  void dispose() {
    _waveTicker.dispose();
    WidgetsBinding.instance.cancelFrameCallbackWithId(0); // no-op; cleanup via mounted check
    context.read<WebRtcProvider>().removeListener(_onWebRtcChanged);
    super.dispose();
  }

  void _onWebRtcChanged() {
    if (!mounted) return;
    final provider = context.read<WebRtcProvider>();
    if (provider.status == WebRtcCallStatus.idle ||
        provider.status == WebRtcCallStatus.ended) {
      Navigator.of(context).pop();
    }
  }

  // ── Average frame render time from recent timestamps ─────────────────────
  double _avgFrameMs() {
    if (_frameTimes.length < 2) return 0;
    final deltas = <int>[];
    for (var i = 1; i < _frameTimes.length; i++) {
      deltas.add(_frameTimes[i] - _frameTimes[i - 1]);
    }
    return deltas.reduce((a, b) => a + b) / deltas.length;
  }

  @override
  Widget build(BuildContext context) {
    // Read once — these are stable for the lifetime of the call.
    final webRtc = context.read<WebRtcProvider>();
    final isVideo = webRtc.currentCallType == 'video';
    final name = webRtc.callerUsername ?? 'Vaani User';
    final avatarLetter = name.isEmpty ? '?' : name[0].toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: Stack(
        children: [
          // ── Video / audio background — RepaintBoundary isolates it fully ──
          Positioned.fill(
            child: RepaintBoundary(
              child: isVideo
                  ? _VideoBackground(renderer: webRtc.remoteRenderer)
                  : _AudioBackground(
                      avatarLetter: avatarLetter,
                      waveProgress: _waveProgress,
                    ),
            ),
          ),

          // Gradient scrim — const, never rebuilds
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x59000000),
                    Colors.transparent,
                    Color(0x8C000000),
                  ],
                ),
              ),
            ),
          ),

          // ── UI overlay ──────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Timer reads from ValueNotifier — zero provider rebuilds.
                _CallTopBar(
                  name: name,
                  durationNotifier: webRtc.callDurationNotifier,
                  isRemoteListening: webRtc.isRemoteListening,
                ),

                if (isVideo && webRtc.userRole == 'deaf')
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange, size: 15),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Video call: camera is used for video. '
                            'Switch to audio call for sign detection.',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11.5,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // Conversion sheet: transcript + signs both via ValueNotifier.
                _ConversionSheet(
                  expanded: _sheetExpanded,
                  transcriptNotifier: webRtc.transcriptNotifier,
                  signSegmentsNotifier: webRtc.signSegmentsNotifier,
                  userRole: webRtc.userRole,
                  onToggle: () =>
                      setState(() => _sheetExpanded = !_sheetExpanded),
                ),

                const SizedBox(height: 12),

                // Control dock — only rebuilds on mute/speaker/video change.
                Selector<WebRtcProvider, (bool, bool, bool)>(
                  selector: (_, p) =>
                      (p.isMuted, p.isSpeakerOn, p.isVideoEnabled),
                  builder: (_, data, __) => _CallControlDock(
                    isMuted: data.$1,
                    isSpeakerOn: data.$2,
                    isVideoEnabled: data.$3,
                    showSwitchCamera: isVideo && data.$3,
                    onMuteTap: webRtc.toggleMute,
                    onSpeakerTap: webRtc.toggleSpeaker,
                    onVideoTap: webRtc.toggleVideo,
                    onSwitchCameraTap: webRtc.switchCamera,
                    onEndTap: webRtc.endCall,
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),

          // Local PIP (video call only)
          if (isVideo)
            Positioned(
              top: 90,
              right: 14,
              child: RepaintBoundary(
                child: _LocalPip(renderer: webRtc.localRenderer),
              ),
            ),

          // Performance monitor overlay (tap to toggle)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() => _perfVisible = !_perfVisible),
              child: _PerfOverlay(
                visible: _perfVisible,
                fps: _displayFps,
                avgFrameMs: _avgFrameMs(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Video background — stable StatelessWidget inside RepaintBoundary ─────────

class _VideoBackground extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const _VideoBackground({required this.renderer});

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      placeholderBuilder: (_) => const ColoredBox(
        color: Color(0xFF1F2C34),
        child: Center(
          child: Icon(Icons.person, size: 84, color: Color(0xFF8696A0)),
        ),
      ),
    );
  }
}

// ── Audio background — waveProgress passed in, no provider access ─────────────

class _AudioBackground extends StatelessWidget {
  final String avatarLetter;
  final double waveProgress;
  const _AudioBackground(
      {required this.avatarLetter, required this.waveProgress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111B21), Color(0xFF202C33)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 62,
              backgroundColor: const Color(0xFF2A3942),
              child: Text(
                avatarLetter,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 26),
            // RepaintBoundary isolates waveform from avatar/background repaints.
            RepaintBoundary(
              child: _Waveform(progress: waveProgress),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar — uses ValueListenableBuilder for timer; never reads provider ─────

class _CallTopBar extends StatelessWidget {
  final String name;
  final ValueNotifier<Duration> durationNotifier;
  final bool isRemoteListening;

  const _CallTopBar({
    required this.name,
    required this.durationNotifier,
    required this.isRemoteListening,
  });

  static String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final badgeText =
        isRemoteListening ? 'Listening to caller' : 'Live translation on';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              // Only the timer text rebuilds — rest is static.
              ValueListenableBuilder<Duration>(
                valueListenable: durationNotifier,
                builder: (_, dur, __) => Text(
                  _fmt(dur),
                  style: const TextStyle(
                      color: Color(0xFFD1D7DB), fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                      color: Color(0xFF9CFCC2),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Local PIP ─────────────────────────────────────────────────────────────────

class _LocalPip extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const _LocalPip({required this.renderer});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 116,
        height: 166,
        child: RTCVideoView(
          renderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          placeholderBuilder: (_) =>
              const ColoredBox(color: Color(0xFF111B21)),
        ),
      ),
    );
  }
}

// ── Conversion sheet — reads only ValueNotifiers, zero provider rebuilds ──────

class _ConversionSheet extends StatelessWidget {
  final bool expanded;
  final ValueNotifier<String> transcriptNotifier;
  final ValueNotifier<List<SignImageSegment>> signSegmentsNotifier;
  final String userRole;
  final VoidCallback onToggle;

  const _ConversionSheet({
    required this.expanded,
    required this.transcriptNotifier,
    required this.signSegmentsNotifier,
    required this.userRole,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDeaf = userRole == 'deaf';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text('Live Conversion',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: const Color(0xFFD1D7DB),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            // Transcript text — ValueListenableBuilder, no provider rebuild.
            ValueListenableBuilder<String>(
              valueListenable: transcriptNotifier,
              builder: (_, transcript, __) => _ConversionCard(
                title: isDeaf ? 'Caller said' : 'You said',
                subtitle: transcript.isEmpty
                    ? (isDeaf
                        ? 'Listening to caller…'
                        : 'Speak to be translated…')
                    : transcript,
                // Sign strip reads its own notifier internally.
                child: _SignStrip(notifier: signSegmentsNotifier),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConversionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ConversionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF8696A0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          child,
        ],
      ),
    );
  }
}

// ── Sign strip — reads ValueNotifier directly ────────────────────────────────

class _SignStrip extends StatelessWidget {
  final ValueNotifier<List<SignImageSegment>> notifier;
  const _SignStrip({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SignImageSegment>>(
      valueListenable: notifier,
      builder: (_, segments, __) {
        if (segments.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 8),
            scrollDirection: Axis.horizontal,
            itemCount: segments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final seg = segments[i];
              if (seg.isWordSpace) return const SizedBox(width: 12);
              if (seg.imageBytes == null) return const SizedBox.shrink();
              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(2),
                child: Image.memory(
                  seg.imageBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Call control dock ─────────────────────────────────────────────────────────

class _CallControlDock extends StatelessWidget {
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool showSwitchCamera;
  final VoidCallback onMuteTap;
  final VoidCallback onSpeakerTap;
  final VoidCallback onVideoTap;
  final VoidCallback onSwitchCameraTap;
  final VoidCallback onEndTap;

  const _CallControlDock({
    required this.isMuted,
    required this.isSpeakerOn,
    required this.isVideoEnabled,
    required this.showSwitchCamera,
    required this.onMuteTap,
    required this.onSpeakerTap,
    required this.onVideoTap,
    required this.onSwitchCameraTap,
    required this.onEndTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _DockButton(
              icon: isMuted ? Icons.mic_off : Icons.mic,
              active: isMuted,
              onTap: onMuteTap),
          _DockButton(
              icon: isSpeakerOn ? Icons.volume_up : Icons.hearing_disabled,
              active: isSpeakerOn,
              onTap: onSpeakerTap),
          _DockButton(
              icon: isVideoEnabled ? Icons.videocam : Icons.videocam_off,
              active: isVideoEnabled,
              onTap: onVideoTap),
          if (showSwitchCamera)
            _DockButton(
                icon: Icons.cameraswitch,
                active: false,
                onTap: onSwitchCameraTap),
          _DockButton(
              icon: Icons.call_end,
              active: true,
              color: const Color(0xFFE0245E),
              onTap: onEndTap),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  const _DockButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor =
        color ?? (active ? const Color(0xFF25D366) : const Color(0xFF2A3942));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// ── Waveform — pure, receives progress as param, ~12fps from parent ───────────

class _Waveform extends StatelessWidget {
  final double progress;
  const _Waveform({required this.progress});

  @override
  Widget build(BuildContext context) {
    final bars = List<double>.generate(
      16,
      (i) => (0.25 + 0.75 * (0.5 + 0.5 * math.sin(i * 0.7 + progress * 10)))
          .clamp(0.25, 1.0),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: bars
          .map((h) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 4,
                  height: 20 + 36 * h,
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF25D366).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ── Performance monitor overlay ───────────────────────────────────────────────

class _PerfOverlay extends StatelessWidget {
  final bool visible;
  final double fps;
  final double avgFrameMs;

  const _PerfOverlay({
    required this.visible,
    required this.fps,
    required this.avgFrameMs,
  });

  @override
  Widget build(BuildContext context) {
    // Always render the tap-target dot; expand to show stats when visible.
    final bool lagDetected = fps > 0 && fps < 24;

    return Container(
      padding: visible
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: lagDetected
            ? Colors.red.withValues(alpha: 0.75)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: visible
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _perfRow('FPS', fps.toStringAsFixed(1),
                    fps > 0 && fps < 24 ? Colors.red : Colors.greenAccent),
                _perfRow('Frame', '${avgFrameMs.toStringAsFixed(1)} ms',
                    avgFrameMs > 33 ? Colors.orange : Colors.greenAccent),
              ],
            )
          : Icon(
              lagDetected ? Icons.warning_amber : Icons.monitor_heart_outlined,
              color: lagDetected ? Colors.red : Colors.white54,
              size: 14,
            ),
    );
  }

  Widget _perfRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label  ',
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
