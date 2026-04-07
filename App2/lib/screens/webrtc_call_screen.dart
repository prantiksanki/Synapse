import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../providers/webrtc_provider.dart';
import '../widgets/sign_language_panel.dart';

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

  // Received sign overlay state
  bool _signOverlayVisible = false;
  ReceivedSignItem? _overlaySign;
  Timer? _signOverlayTimer;

  @override
  void initState() {
    super.initState();

    _waveTicker = createTicker(_onWaveTick)..start();
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<WebRtcProvider>();
      provider.addListener(_onWebRtcChanged);
      provider.receivedSignNotifier.addListener(_onReceivedSign);
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

  void _onReceivedSign() {
    if (!mounted) return;
    final item = context.read<WebRtcProvider>().receivedSignNotifier.value;
    if (item == null) return;
    _signOverlayTimer?.cancel();
    setState(() {
      _overlaySign = item;
      _signOverlayVisible = true;
    });
    _signOverlayTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _signOverlayVisible = false);
    });
  }

  @override
  void dispose() {
    _waveTicker.dispose();
    _signOverlayTimer?.cancel();
    final provider = context.read<WebRtcProvider>();
    provider.removeListener(_onWebRtcChanged);
    provider.receivedSignNotifier.removeListener(_onReceivedSign);
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

  double _avgFrameMs() {
    if (_frameTimes.length < 2) return 0;
    final deltas = <int>[];
    for (var i = 1; i < _frameTimes.length; i++) {
      deltas.add(_frameTimes[i] - _frameTimes[i - 1]);
    }
    return deltas.reduce((a, b) => a + b) / deltas.length;
  }

  void _openSignPanel(BuildContext ctx, WebRtcProvider provider) {
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => SignLanguagePanel(
        onSignSelected: (gifPath, label) {
          // Use the modal's own context to pop only the bottom sheet,
          // not the outer call screen.
          Navigator.of(sheetCtx).pop();
          provider.sendSign(gifPath, label);
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Sent: $label'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF25D366),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webRtc = context.read<WebRtcProvider>();
    final isVideo = webRtc.currentCallType == 'video';
    final name = webRtc.callerUsername ?? 'Synapse User';
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

          // Gradient scrim
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
                _CallTopBar(
                  name: name,
                  durationNotifier: webRtc.callDurationNotifier,
                  isRemoteListening: webRtc.isRemoteListening,
                ),

                const Spacer(),

                // Live transcript sheet
                _TranscriptSheet(
                  expanded: _sheetExpanded,
                  transcriptNotifier: webRtc.transcriptNotifier,
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
                    onSignTap: () => _openSignPanel(context, webRtc),
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

          // ── Received sign overlay — appears for 3.5s then fades ─────────
          if (_overlaySign != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _signOverlayVisible ? 1.0 : 0.0,
                  onEnd: () {
                    if (!_signOverlayVisible && mounted) {
                      setState(() => _overlaySign = null);
                    }
                  },
                  child: Center(
                    child: _ReceivedSignCard(sign: _overlaySign!),
                  ),
                ),
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

// ── Video background ──────────────────────────────────────────────────────────

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

// ── Audio background ──────────────────────────────────────────────────────────

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
            RepaintBoundary(child: _Waveform(progress: waveProgress)),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

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
              ValueListenableBuilder<Duration>(
                valueListenable: durationNotifier,
                builder: (_, dur, __) => Text(
                  _fmt(dur),
                  style: const TextStyle(
                      color: Color(0xFFD1D7DB), fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              if (isRemoteListening)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Live transcript on',
                    style: TextStyle(
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

// ── Transcript sheet ──────────────────────────────────────────────────────────

class _TranscriptSheet extends StatelessWidget {
  final bool expanded;
  final ValueNotifier<String> transcriptNotifier;
  final VoidCallback onToggle;

  const _TranscriptSheet({
    required this.expanded,
    required this.transcriptNotifier,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
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
                  const Text('Live Transcript',
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
            ValueListenableBuilder<String>(
              valueListenable: transcriptNotifier,
              builder: (_, transcript, __) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2C34),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Other person said',
                        style: TextStyle(
                            color: Color(0xFF8696A0),
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      transcript.isEmpty
                          ? 'Listening for speech…'
                          : transcript,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
  final VoidCallback onSignTap;

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
    required this.onSignTap,
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
              icon: Icons.sign_language,
              active: false,
              onTap: onSignTap),
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

// ── Received sign overlay card ────────────────────────────────────────────────

class _ReceivedSignCard extends StatelessWidget {
  final ReceivedSignItem sign;
  const _ReceivedSignCard({required this.sign});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111B21).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF25D366), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Sign received',
            style: TextStyle(
              color: Color(0xFF25D366),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              sign.gifPath,
              width: 140,
              height: 140,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 140,
                height: 140,
                child: Icon(Icons.sign_language,
                    color: Color(0xFF25D366), size: 60),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            sign.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Waveform ──────────────────────────────────────────────────────────────────

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
                    color: const Color(0xFF25D366).withValues(alpha: 0.85),
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
                color: valueColor,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
