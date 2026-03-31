import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class OnboardingUsernameStep extends StatefulWidget {
  final int step;
  final int total;
  final bool isLoading;
  final void Function(String) onFinish;
  final VoidCallback onBack;

  const OnboardingUsernameStep({
    super.key,
    required this.step,
    required this.total,
    required this.isLoading,
    required this.onFinish,
    required this.onBack,
  });

  @override
  State<OnboardingUsernameStep> createState() => _OnboardingUsernameStepState();
}

class _OnboardingUsernameStepState extends State<OnboardingUsernameStep> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final val = _ctrl.text.trim();
    if (val.isEmpty) {
      setState(() => _error = 'Please enter a username.');
      return;
    }
    if (val.contains(' ')) {
      setState(() => _error = 'No spaces allowed.');
      return;
    }
    if (val.length < 3) {
      setState(() => _error = 'At least 3 characters.');
      return;
    }
    widget.onFinish(val);
  }

  @override
  Widget build(BuildContext context) {
    const backgroundTop = Color(0xFFF5F0FF);
    const backgroundBottom = Color(0xFFFCF8FF);
    const titleColor = Color(0xFF2F285A);
    const accent = Color(0xFF4B3FE0);
    const accentDeep = Color(0xFF3E31D6);
    const metaColor = Color(0xFF685E8F);
    const hintColor = Color(0xFFB7B0D5);
    const cardBorder = Color(0xFFE7DFFC);
    const errorColor = Color(0xFFD84C6F);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [backgroundTop, backgroundBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.78,
                    colors: [
                      accent.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 148,
            left: -36,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          Positioned(
            top: 224,
            right: -44,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.05),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 18,
            child: IgnorePointer(
              child: SizedBox(
                height: 124,
                child: CustomPaint(
                  painter: _Step14WavePainter(
                    accent: accent,
                    accentDeep: accentDeep,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              'FINALIZING ACCOUNT',
                              style: TextStyle(
                                color: metaColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                            Text(
                              'STEP 14 OF 14',
                              style: TextStyle(
                                color: metaColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: widget.step / widget.total,
                            minHeight: 3,
                            backgroundColor: accent.withValues(alpha: 0.16),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onBack,
                              child: const SizedBox(
                                width: 54,
                                height: 54,
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: accent,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 38),
                        Center(
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.95),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.10),
                                  blurRadius: 34,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Lottie.asset(
                                'assets/mascotAnimation.json',
                                width: 160,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        const Text(
                          'Almost there!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Choose your username',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Used to identify you during calls.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: metaColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: _error == null ? cardBorder : errorColor,
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.05),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _ctrl,
                            enabled: !widget.isLoading,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            style: const TextStyle(
                              color: titleColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'e.g. prantik_1',
                              hintStyle: TextStyle(
                                color: hintColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(left: 18, right: 8),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: metaColor,
                                  size: 24,
                                ),
                              ),
                              prefixIconConstraints:
                                  BoxConstraints(minWidth: 56),
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 10, vertical: 21),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _error ?? 'No spaces  |  At least 3 characters',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: _error == null ? hintColor : errorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          height: 74,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(38),
                              gradient: LinearGradient(
                                colors: widget.isLoading
                                    ? [
                                        accent.withValues(alpha: 0.45),
                                        accentDeep.withValues(alpha: 0.45),
                                      ]
                                    : const [accentDeep, Color(0xFF7A73F7)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.22),
                                  blurRadius: 24,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: widget.isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.80),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(38),
                                ),
                              ),
                              child: Text(
                                widget.isLoading ? 'Setting up...' : 'Get Started',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 90),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Step14WavePainter extends CustomPainter {
  final Color accent;
  final Color accentDeep;

  const _Step14WavePainter({
    required this.accent,
    required this.accentDeep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.16),
          accentDeep.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.28, 0.7, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          accent.withValues(alpha: 0.08),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.14,
        size.height * 0.30,
        size.width * 0.28,
        size.height * 0.90,
        size.width * 0.43,
        size.height * 0.58,
      )
      ..cubicTo(
        size.width * 0.55,
        size.height * 0.34,
        size.width * 0.70,
        size.height * 0.18,
        size.width * 0.84,
        size.height * 0.56,
      )
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.76,
        size.width * 0.96,
        size.height * 0.84,
        size.width,
        size.height * 0.80,
      );

    canvas.drawPath(path, basePaint);
    canvas.drawPath(path, highlightPaint);

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _Step14WavePainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.accentDeep != accentDeep;
  }
}
