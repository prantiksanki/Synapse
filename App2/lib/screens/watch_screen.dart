import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../providers/watch_mode_provider.dart';
import '../services/sign_image_service.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  // Stable instance — never recreated on provider notifications.
  final _reelView = const _ReelView();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WatchModeProvider>().initialize();
    });
  }

  @override
  void dispose() {
    context.read<WatchModeProvider>().stopPlaying();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<WatchModeProvider, WatchModeState>(
      selector: (_, w) => w.state,
      builder: (_, state, __) {
        if (state == WatchModeState.permissionDenied) {
          return const _PermissionDeniedScaffold();
        }
        return _reelView;
      },
    );
  }
}

// ── Permission Denied ─────────────────────────────────────────────────────────

class _PermissionDeniedScaffold extends StatelessWidget {
  const _PermissionDeniedScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Watch & Learn Signs',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_off_rounded,
                    color: Color(0xFFFF5252), size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Microphone Permission Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'This feature needs microphone access to convert your speech into sign language in real time.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.obPrimaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reel View (shell) ─────────────────────────────────────────────────────────

class _ReelView extends StatefulWidget {
  const _ReelView();

  @override
  State<_ReelView> createState() => _ReelViewState();
}

class _ReelViewState extends State<_ReelView> {
  WatchModeProvider? _watchProvider;

  // The full ordered segment list for the current utterance.
  List<SignImageSegment> _segments = [];
  // Index of the sign currently being highlighted.
  int _activeIndex = -1;

  final List<Timer> _sequenceTimers = [];

  // How long each sign is highlighted before advancing.
  static const Duration _perSignDuration = Duration(milliseconds: 600);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.read<WatchModeProvider>();
    if (_watchProvider != p) {
      _watchProvider?.removeListener(_onProviderUpdate);
      _watchProvider = p;
      p.addListener(_onProviderUpdate);
    }
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final segs = _watchProvider!.segments;
    // Only react when a genuinely new batch arrives.
    if (segs.isEmpty || identical(segs, _segments)) return;
    _cancelSequence();
    setState(() {
      _segments = segs;
      _activeIndex = -1;
    });
    _startSequence(segs);
  }

  void _startSequence(List<SignImageSegment> segs) {
    // Filter to visual-only (skip word-space markers).
    final visual = [
      for (var i = 0; i < segs.length; i++)
        if (!segs[i].isWordSpace) i,
    ];

    for (var vi = 0; vi < visual.length; vi++) {
      final segIdx = visual[vi];
      final t = Timer(_perSignDuration * vi, () {
        if (!mounted) return;
        setState(() => _activeIndex = segIdx);
      });
      _sequenceTimers.add(t);
    }
    // Clear active highlight after the last sign has been shown.
    if (visual.isNotEmpty) {
      final clearAt = _perSignDuration * visual.length;
      _sequenceTimers.add(Timer(clearAt, () {
        if (!mounted) return;
        setState(() => _activeIndex = -1);
      }));
    }
  }

  void _cancelSequence() {
    for (final t in _sequenceTimers) {
      t.cancel();
    }
    _sequenceTimers.clear();
  }

  @override
  void dispose() {
    _watchProvider?.removeListener(_onProviderUpdate);
    _cancelSequence();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Crystal-clear full-screen video ────────────────────────────────
        Selector<WatchModeProvider,
            ({VideoPlayerController? ctrl, WatchModeState state})>(
          selector: (_, w) => (ctrl: w.videoController, state: w.state),
          builder: (_, data, __) =>
              _FullScreenVideo(controller: data.ctrl, state: data.state),
        ),

        // ── Top bar (back + title) ─────────────────────────────────────────
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(),
        ),

        // ── Professional sign tray (bottom half) ──────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _SignTray(
            segments: _segments,
            activeIndex: _activeIndex,
          ),
        ),
      ],
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Text(
              'Watch & Learn Signs',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sign Tray ─────────────────────────────────────────────────────────────────
//
// Layout:
//   ┌──────────────────────────────────────────────────┐
//   │  [transcript text]                               │  ← text overlay
//   │  [status chip]                                   │
//   │                                                  │
//   │  ╔══╗  ╔══╗  ╔══╗  ╔══╗  ╔══╗  …               │  ← sign row
//   │  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║                  │
//   │  ╚══╝  ╚══╝  ╚══╝  ╚══╝  ╚══╝                  │
//   └──────────────────────────────────────────────────┘

class _SignTray extends StatelessWidget {
  final List<SignImageSegment> segments;
  final int activeIndex;

  const _SignTray({required this.segments, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF0000000), Color(0x99000000), Colors.transparent],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Transcript + status
              _BottomMeta(),
              if (segments.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SignRow(segments: segments, activeIndex: activeIndex),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom meta (transcript + status chip) ────────────────────────────────────

class _BottomMeta extends StatelessWidget {
  const _BottomMeta();

  @override
  Widget build(BuildContext context) {
    return Selector<WatchModeProvider,
        ({
          String transcript,
          WatchModeState state,
          String message,
          String sourceLabel,
          String engineLabel,
          String gloss,
        })>(
      selector: (_, w) => (
        transcript: w.rawTranscript,
        state: w.state,
        message: w.statusMessage,
        sourceLabel: w.transcriptSourceLabel,
        engineLabel: w.conversionEngineLabel,
        gloss: w.lastGloss,
      ),
      builder: (_, data, __) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.transcript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                data.transcript,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  shadows: [
                    Shadow(
                        blurRadius: 8,
                        color: Colors.black,
                        offset: Offset(0, 1))
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (data.gloss.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Gloss: ${data.gloss}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaBadge(
                icon: Icons.graphic_eq_rounded,
                label: data.sourceLabel,
              ),
              _MetaBadge(
                icon: Icons.memory_rounded,
                label: data.engineLabel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _StatusChip(state: data.state, message: data.message),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x332A353B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sign Row ──────────────────────────────────────────────────────────────────
//
// Horizontally scrollable row of sign cards.
// The active card is highlighted and slightly larger.

class _SignRow extends StatefulWidget {
  final List<SignImageSegment> segments;
  final int activeIndex;

  const _SignRow({required this.segments, required this.activeIndex});

  @override
  State<_SignRow> createState() => _SignRowState();
}

class _SignRowState extends State<_SignRow> {
  final ScrollController _scroll = ScrollController();
  static const double _cardW = 72;
  static const double _cardH = 88;
  static const double _gap = 8;

  @override
  void didUpdateWidget(covariant _SignRow old) {
    super.didUpdateWidget(old);
    // Auto-scroll to keep active card visible.
    if (widget.activeIndex != old.activeIndex && widget.activeIndex >= 0) {
      _scrollToActive(widget.activeIndex);
    }
    // When new segments arrive, scroll to the start.
    if (!identical(widget.segments, old.segments)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });
    }
  }

  void _scrollToActive(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = idx * (_cardW + _gap);
      final viewW = _scroll.position.viewportDimension;
      final centred = target - viewW / 2 + _cardW / 2;
      _scroll.animateTo(
        centred.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardH + 4, // extra for active scale
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.segments.length,
        separatorBuilder: (_, i) {
          // Word-space gap: render as a small divider line.
          final seg = widget.segments[i];
          if (seg.isWordSpace) return const SizedBox(width: 0);
          final next = i + 1 < widget.segments.length
              ? widget.segments[i + 1]
              : null;
          if (next != null && next.isWordSpace) {
            return Container(
              width: 20,
              alignment: Alignment.center,
              child: Container(
                width: 1,
                height: 36,
                color: Colors.white24,
              ),
            );
          }
          return SizedBox(width: _gap);
        },
        itemBuilder: (_, i) {
          final seg = widget.segments[i];
          if (seg.isWordSpace) return const SizedBox.shrink();
          final isActive = i == widget.activeIndex;
          return _SignCard(
            seg: seg,
            isActive: isActive,
            width: _cardW,
            height: _cardH,
          );
        },
      ),
    );
  }
}

// ── Sign Card ─────────────────────────────────────────────────────────────────

class _SignCard extends StatelessWidget {
  final SignImageSegment seg;
  final bool isActive;
  final double width;
  final double height;

  const _SignCard({
    required this.seg,
    required this.isActive,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppConfig.obPrimary;
    const inactiveColor = Color(0xFF2C3C44);

    final borderColor = isActive ? activeColor : Colors.white24;
    final bgColor = isActive
        ? activeColor.withValues(alpha: 0.18)
        : inactiveColor.withValues(alpha: 0.75);

    return AnimatedScale(
      scale: isActive ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isActive ? 2.0 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                child: _segImage(seg),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                seg.isGif
                    ? (seg.word?.toLowerCase() ?? '')
                    : (seg.char ?? ''),
                style: TextStyle(
                  color: isActive ? activeColor : Colors.white70,
                  fontSize: seg.isGif ? 9 : 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segImage(SignImageSegment seg) {
    if (seg.isGif && seg.gifAssetPath != null) {
      return Image.asset(
        seg.gifAssetPath!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.sign_language_rounded,
          color: Colors.white38,
          size: 28,
        ),
      );
    }
    if (seg.imageBytes != null) {
      return Image.memory(
        seg.imageBytes!,
        fit: BoxFit.contain,
      );
    }
    return const Icon(Icons.help_outline_rounded,
        color: Colors.white38, size: 28);
  }
}

// ── Full-Screen Video ─────────────────────────────────────────────────────────
//
// Renders at the device's native pixel resolution.
// No FittedBox scaling, no LayoutBuilder recomputation — just AspectRatio
// stretched to fill the screen with ClipRect preventing overflow artefacts.

class _FullScreenVideo extends StatelessWidget {
  final VideoPlayerController? controller;
  final WatchModeState state;

  const _FullScreenVideo({required this.controller, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == WatchModeState.loading || controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: AppConfig.obPrimary),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller!.value.size?.width ?? MediaQuery.of(context).size.width,
          height: controller!.value.size?.height ?? MediaQuery.of(context).size.height,
          child: VideoPlayer(controller!),
        ),
      ),
    );
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final WatchModeState state;
  final String message;

  const _StatusChip({required this.state, required this.message});

  Color _color() {
    switch (state) {
      case WatchModeState.playing:
        if (message.contains('Converting')) return const Color(0xFFAB47BC);
        return const Color(0xFF42A5F5);
      case WatchModeState.listening:
        return const Color(0xFF8E24AA);
      case WatchModeState.paused:
        return Colors.white54;
      case WatchModeState.loading:
        return AppConfig.obPrimary;
      case WatchModeState.error:
        return const Color(0xFFFF5252);
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            message,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
