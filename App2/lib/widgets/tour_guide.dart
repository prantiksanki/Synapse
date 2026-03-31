import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Pref key ─────────────────────────────────────────────────────────────────
const _kTourDoneKey = 'app_tour_done';

// ── Tour step definition ──────────────────────────────────────────────────────

class TourStep {
  /// The GlobalKey of the widget to highlight. Null = no spotlight.
  final GlobalKey? targetKey;

  /// Mascot speech bubble text.
  final String message;

  /// Extra padding around the spotlight rect.
  final double spotPadding;

  const TourStep({
    this.targetKey,
    required this.message,
    this.spotPadding = 14,
  });
}

// ── TourGuide overlay widget ──────────────────────────────────────────────────

class TourGuide extends StatefulWidget {
  final List<TourStep> steps;
  final Widget child;

  const TourGuide({
    super.key,
    required this.steps,
    required this.child,
  });

  @override
  State<TourGuide> createState() => _TourGuideState();
}

class _TourGuideState extends State<TourGuide> with TickerProviderStateMixin {
  bool _loading = true;
  bool _visible = false;
  int _step = 0;

  // Spotlight rect driven by a single Tween animation — no setState in listener
  late final AnimationController _spotController;
  late Animation<Rect?> _spotAnim;

  late final AnimationController _mascotBounce;
  late final AnimationController _bubbleFade;

  Rect _fromRect = Rect.zero;
  Rect _toRect = Rect.zero;

  @override
  void initState() {
    super.initState();

    _spotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _spotAnim = RectTween(begin: Rect.zero, end: Rect.zero).animate(
      CurvedAnimation(parent: _spotController, curve: Curves.easeInOutCubic),
    );

    _mascotBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _bubbleFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _checkFirstLaunch();
  }

  @override
  void dispose() {
    _spotController.dispose();
    _mascotBounce.dispose();
    _bubbleFade.dispose();
    super.dispose();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kTourDoneKey) ?? false;
    if (!mounted) return;
    if (done) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = false;
      _visible = true;
      _step = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _snapToStep(0));
  }

  Rect _rectFor(int index) {
    if (index >= widget.steps.length) return Rect.zero;
    final step = widget.steps[index];
    final key = step.targetKey;
    if (key == null || key.currentContext == null) return Rect.zero;
    final box = key.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    final pos = box.localToGlobal(Offset.zero);
    final p = step.spotPadding;
    return Rect.fromLTWH(
      pos.dx - p,
      pos.dy - p,
      box.size.width + p * 2,
      box.size.height + p * 2,
    );
  }

  void _rebuildSpotAnim() {
    _spotAnim = RectTween(begin: _fromRect, end: _toRect).animate(
      CurvedAnimation(parent: _spotController, curve: Curves.easeInOutCubic),
    );
  }

  void _snapToStep(int index) {
    final rect = _rectFor(index);
    setState(() {
      _step = index;
      _fromRect = rect;
      _toRect = rect;
    });
    _rebuildSpotAnim();
    _bubbleFade.forward(from: 0);
  }

  void _animateToStep(int index) {
    _bubbleFade.reverse().then((_) {
      if (!mounted) return;
      final from = _spotAnim.value ?? _fromRect;
      final to = _rectFor(index);
      setState(() {
        _step = index;
        _fromRect = from;
        _toRect = to;
      });
      _rebuildSpotAnim();
      _spotController.forward(from: 0).then((_) {
        if (mounted) _bubbleFade.forward(from: 0);
      });
    });
  }

  void _next() {
    if (_step < widget.steps.length - 1) {
      _animateToStep(_step + 1);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_step > 0) _animateToStep(_step - 1);
  }

  Future<void> _finish() async {
    await _bubbleFade.reverse();
    if (!mounted) return;
    setState(() => _visible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTourDoneKey, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.child;
    return Stack(
      children: [
        widget.child,
        if (_visible) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final step = widget.steps[_step];
    final isFirst = _step == 0;
    final isLast = _step == widget.steps.length - 1;

    const panelH = 200.0;
    const mascotH = 120.0;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // ── Scrim + spotlight ──────────────────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: _next,
                child: AnimatedBuilder(
                  animation: _spotAnim,
                  builder: (context, _) => CustomPaint(
                    painter: _SpotlightPainter(rect: _spotAnim.value ?? Rect.zero),
                    size: size,
                  ),
                ),
              ),
            ),

            // ── Bottom panel (speech bubble + buttons) ─────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FadeTransition(
                opacity: _bubbleFade,
                child: Container(
                  height: panelH,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111A14),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                      top: BorderSide(color: Color(0xFF2A3D2E), width: 1.5),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step dots
                      Center(
                        child: _StepDots(
                          total: widget.steps.length,
                          current: _step,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Message — left-padded to make room for mascot
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 108),
                          child: Text(
                            step.message,
                            style: const TextStyle(
                              color: Color(0xFFF1F7E8),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Buttons row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isFirst) ...[
                            _TourButton(
                              label: 'Prev',
                              primary: false,
                              onTap: _prev,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _TourButton(
                            label: isLast ? 'Done' : 'Next',
                            primary: true,
                            onTap: _next,
                          ),
                          const SizedBox(width: 8),
                          _TourButton(
                            label: 'Skip',
                            primary: false,
                            onTap: _finish,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Mascot (bottom-left, floats above panel) ───────────────────
            Positioned(
              left: 16,
              bottom: panelH - mascotH * 0.3,
              child: FadeTransition(
                opacity: _bubbleFade,
                child: AnimatedBuilder(
                  animation: _mascotBounce,
                  builder: (context, child) {
                    final bounce = math.sin(_mascotBounce.value * math.pi) * 4;
                    return Transform.translate(
                      offset: Offset(0, -bounce),
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/visit.gif',
                    height: mascotH,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Spotlight painter ─────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect rect;
  const _SpotlightPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final overlay = rect == Rect.zero
        ? fullPath
        : () {
            final radius = math.min(rect.width, rect.height) * 0.14;
            final cutout = Path()
              ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
            return Path.combine(PathOperation.difference, fullPath, cutout);
          }();

    canvas.drawPath(
      overlay,
      Paint()..color = const Color(0xC7000000),
    );

    if (rect != Rect.zero) {
      final radius = math.min(rect.width, rect.height) * 0.14;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()
          ..color = const Color(0xA695DE28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.rect != rect;
}

// ── Step dots ─────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int total;
  final int current;

  const _StepDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF95DE28) : const Color(0xFF2A3D2E),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

// ── Tour buttons ──────────────────────────────────────────────────────────────

class _TourButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _TourButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF95DE28) : const Color(0xFF1A2820),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: primary ? const Color(0xFF95DE28) : const Color(0xFF2A3D2E),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? const Color(0xFF0A1210) : const Color(0xFF7A9280),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
