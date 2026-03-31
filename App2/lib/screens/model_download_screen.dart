import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/detection_provider.dart';
import 'welcome_screen.dart';

/// Shown on first launch when T5 model files are not yet on device.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen>
    with TickerProviderStateMixin {
  bool _started = false;
  bool _failed = false;
  String _errorMessage = '';

  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_started) return;
    _started = true;
    _failed = false;

    final provider = context.read<DetectionProvider>();

    try {
      await provider.downloadAndLoadGrammarModel();
      if (!mounted) return;

      if (provider.grammarStatus == GrammarModelStatus.ready ||
          provider.grammarStatus == GrammarModelStatus.error) {
        _goToDetection();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _goToDetection() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1210),
      body: SafeArea(
        child: Consumer<DetectionProvider>(
          builder: (context, provider, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  const _Header(),
                  const Spacer(),

                  // ── Central progress ring ────────────────────────────
                  if (!_failed)
                    _ProgressRing(
                      provider: provider,
                      pulseAnim: _pulseAnim,
                      rotateController: _rotateController,
                    ),
                  if (_failed) _ErrorIcon(pulseAnim: _pulseAnim),

                  const SizedBox(height: 36),

                  // ── Status card ──────────────────────────────────────
                  if (!_failed) _StatusCard(provider: provider),
                  if (_failed)
                    _ErrorCard(
                      message: _errorMessage,
                      onRetry: () {
                        setState(() {
                          _started = false;
                          _failed = false;
                          _errorMessage = '';
                        });
                        _startDownload();
                      },
                      onSkip: _goToDetection,
                    ),

                  const Spacer(flex: 2),

                  // ── Footer note ──────────────────────────────────────
                  if (!_failed) const _FooterNote(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          AppConfig.appTitle,
          style: TextStyle(
            color: Color(0xFFF3F7F1),
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One-time setup',
          style: TextStyle(
            color: const Color(0xFFF3F7F1).withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ── Progress ring ───────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  final DetectionProvider provider;
  final Animation<double> pulseAnim;
  final AnimationController rotateController;

  const _ProgressRing({
    required this.provider,
    required this.pulseAnim,
    required this.rotateController,
  });

  @override
  Widget build(BuildContext context) {
    final status = provider.grammarStatus;
    final progress = provider.downloadProgress;
    final isDone = status == GrammarModelStatus.ready;
    final isLoading = status == GrammarModelStatus.loading;

    if (isDone) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        ),
      );
    }

    final double? arcProgress = isDone
        ? 1.0
        : (isLoading ? null : (progress > 0 ? progress : null));

    return AnimatedBuilder(
      animation: Listenable.merge([pulseAnim, rotateController]),
      builder: (context, _) {
        final glowAlpha = 0.25 + pulseAnim.value * 0.20;
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppConfig.obPrimary.withValues(alpha: glowAlpha),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
              // Arc painter
              CustomPaint(
                size: const Size(200, 200),
                painter: _ArcPainter(
                  progress: arcProgress,
                  spinning: arcProgress == null,
                  spinAngle: rotateController.value * 2 * math.pi,
                  isDone: isDone,
                ),
              ),
              // Inner circle
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F1A12),
                  border: Border.all(
                    color: const Color(0xFF1E3021),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppConfig.obPrimary,
                          size: 52,
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.download_rounded,
                              color: AppConfig.obPrimary.withValues(alpha: 0.85),
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            if (arcProgress != null && !isDone)
                              Text(
                                '${(arcProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: AppConfig.obPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            else
                              Text(
                                isLoading ? 'Loading' : '...',
                                style: TextStyle(
                                  color: AppConfig.obPrimary.withValues(alpha: 0.7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
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

class _ArcPainter extends CustomPainter {
  final double? progress;
  final bool spinning;
  final double spinAngle;
  final bool isDone;

  const _ArcPainter({
    required this.progress,
    required this.spinning,
    required this.spinAngle,
    required this.isDone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 7.0;

    // Track
    final trackPaint = Paint()
      ..color = const Color(0xFF1E3021)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Arc
    final arcPaint = Paint()
      ..color = isDone ? AppConfig.obPrimary : AppConfig.obPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (spinning) {
      // Indeterminate spinning arc
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        spinAngle - math.pi / 2,
        math.pi * 1.2,
        false,
        arcPaint,
      );
    } else {
      final sweep = (progress ?? 1.0) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress ||
      old.spinning != spinning ||
      old.spinAngle != spinAngle ||
      old.isDone != isDone;
}

// ── Error icon ──────────────────────────────────────────────────────────────

class _ErrorIcon extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _ErrorIcon({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, _) {
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A0F0F),
            border: Border.all(
              color: const Color(0xFFEF4444).withValues(alpha: 0.5 + pulseAnim.value * 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15 + pulseAnim.value * 0.10),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.wifi_off_rounded,
            color: Color(0xFFEF4444),
            size: 48,
          ),
        );
      },
    );
  }
}

// ── Status card ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final DetectionProvider provider;
  const _StatusCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final status = provider.grammarStatus;
    final message = provider.grammarStatusMessage ?? '';
    final fileLabel = provider.downloadFileLabel;

    final String title;
    final String subtitle;

    switch (status) {
      case GrammarModelStatus.downloading:
        title = 'Downloading Grammar Model';
        subtitle = fileLabel.isNotEmpty ? 'File: $fileLabel' : 'Fetching files…';
      case GrammarModelStatus.loading:
        title = 'Loading Model';
        subtitle = 'Preparing the grammar engine…';
      case GrammarModelStatus.ready:
        title = 'Model Ready';
        subtitle = 'Starting VAANI…';
      default:
        title = 'Preparing Download';
        subtitle = 'Getting ready…';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E3021), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF3F7F1),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.isNotEmpty ? message : subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFF3F7F1).withValues(alpha: 0.5),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Thin progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: status == GrammarModelStatus.downloading && provider.downloadProgress > 0
                  ? provider.downloadProgress
                  : (status == GrammarModelStatus.ready ? 1.0 : null),
              minHeight: 4,
              backgroundColor: const Color(0xFF1E3021),
              valueColor: const AlwaysStoppedAnimation<Color>(AppConfig.obPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error card ──────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF150F0F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A1F1F), width: 1.5),
      ),
      child: Column(
        children: [
          const Text(
            'Download Failed',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.isNotEmpty ? message : 'Check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFF3F7F1).withValues(alpha: 0.45),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Retry Download',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.obPrimary,
                foregroundColor: const Color(0xFF0A1210),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip — use basic mode',
              style: TextStyle(
                color: const Color(0xFFF3F7F1).withValues(alpha: 0.35),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer note ─────────────────────────────────────────────────────────────

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 13,
          color: const Color(0xFFF3F7F1).withValues(alpha: 0.3),
        ),
        const SizedBox(width: 6),
        Text(
          '${AppConfig.t5ModelSizeLabel} · one-time · runs fully offline',
          style: TextStyle(
            color: const Color(0xFFF3F7F1).withValues(alpha: 0.30),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
