import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class EegScreen extends StatefulWidget {
  const EegScreen({super.key});

  @override
  State<EegScreen> createState() => _EegScreenState();
}

class _EegScreenState extends State<EegScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = VideoPlayerController.asset('assets/EEG.mp4')
      ..setLooping(true)
      ..setVolume(1.0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen video ─────────────────────────────────────────────
          _initialized
              ? _FullScreenVideo(controller: _controller)
              : const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6C63FF),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),

          // ── Top gradient + back button ────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 110,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'EEG',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom sheet — coming soon + info cards ───────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomSheet(),
          ),
        ],
      ),
    );
  }
}

// ── Full-Screen Video (same pattern as Watch) ─────────────────────────────────

class _FullScreenVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const _FullScreenVideo({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width ?? MediaQuery.of(context).size.width,
          height: controller.value.size.height ?? MediaQuery.of(context).size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

// ── Bottom Sheet ──────────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black87, Colors.transparent],
          stops: [0.0, 0.7, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coming Soon banner
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1040).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.55),
                    width: 1.3,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: Color(0xFF9D93FF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Coming Soon',
                            style: TextStyle(
                              color: Color(0xFF9D93FF),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Due to the heavy weight of the EEG model, we cannot bundle it in the app yet. We are actively optimising it and will add full EEG-based control in a future update.',
                            style: TextStyle(
                              color: Color(0xFFB0AAD6),
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Three info chips in a row
              Row(
                children: const [
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.bolt_rounded,
                      iconColor: Color(0xFFFBBF24),
                      label: 'Brain-Computer\nInterface',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.sign_language_rounded,
                      iconColor: Color(0xFF34D399),
                      label: 'Assistive\nComm.',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.memory_rounded,
                      iconColor: Color(0xFF60A5FA),
                      label: 'On-Device\nAI',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info Chip (compact, for the reel bottom bar) ──────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
