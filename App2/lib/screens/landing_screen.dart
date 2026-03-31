import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/onboarding_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _nextIntroPage() async {
    if (_currentPage >= 1) return;
    await _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _previousIntroPage() async {
    if (_currentPage <= 0) return;
    await _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToOnboarding() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const OnboardingScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF11181C),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF172126),
                Color(0xFF11181C),
                Color(0xFF0C1216),
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                top: -120,
                left: -40,
                child: _GlowOrb(
                  size: 220,
                  color: Color(0x333AE374),
                ),
              ),
              const Positioned(
                right: -70,
                top: 110,
                child: _GlowOrb(
                  size: 180,
                  color: Color(0x1F9EEF49),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 150,
                child: IgnorePointer(
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.3,
                        colors: [
                          Color(0x223AE374),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (page) {
                            setState(() => _currentPage = page);
                          },
                          children: [
                            _LandingHeroPage(
                              floatController: _floatController,
                              onGetStarted: _nextIntroPage,
                              onAccountTap: _goToOnboarding,
                            ),
                            _LandingMessagePage(
                              floatController: _floatController,
                              onBack: _previousIntroPage,
                              onContinue: _goToOnboarding,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _PageDots(currentPage: _currentPage),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingHeroPage extends StatelessWidget {
  final AnimationController floatController;
  final VoidCallback onGetStarted;
  final VoidCallback onAccountTap;

  const _LandingHeroPage({
    required this.floatController,
    required this.onGetStarted,
    required this.onAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mascotSize = math.min(size.width * 0.48, 220.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Column(
        children: [
          const _TopBrandBar(),
          SizedBox(height: size.height * 0.08),
          AnimatedBuilder(
            animation: floatController,
            builder: (context, child) {
              final offsetY = math.sin(floatController.value * math.pi * 2) * 12;
              return Transform.translate(
                offset: Offset(0, offsetY),
                child: child,
              );
            },
            child: _MascotHero(size: mascotSize),
          ),
          const SizedBox(height: 28),
          Text(
            'vaani',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: const Color(0xFF8EE62A),
                  fontWeight: FontWeight.w800,
                  fontSize: 48,
                  letterSpacing: -1.4,
                ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Learn sign. Speak clearly. Connect faster.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF72808A),
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF182227),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF243138),
                width: 1.3,
              ),
            ),
            child: const Text(
              'Daily practice for real-world communication',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFB6C2C8),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Spacer(),
          _PrimaryCtaButton(
            label: 'GET STARTED',
            onPressed: onGetStarted,
          ),
          const SizedBox(height: 18),
          _SecondaryCtaButton(
            label: 'I ALREADY HAVE AN ACCOUNT',
            onPressed: onAccountTap,
          ),
        ],
      ),
    );
  }
}

class _LandingMessagePage extends StatelessWidget {
  final AnimationController floatController;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _LandingMessagePage({
    required this.floatController,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mascotSize = math.min(size.width * 0.5, 230.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF5E7079),
                size: 38,
              ),
            ),
          ),
          const Spacer(),
          const _SpeechBubble(
            message: "Hi there! I'm Vaani.",
          ),
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: floatController,
            builder: (context, child) {
              final offsetY = math.sin(floatController.value * math.pi * 2) * 10;
              return Transform.translate(
                offset: Offset(0, offsetY),
                child: child,
              );
            },
            child: _MascotHero(size: mascotSize),
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'I will help you practice sign conversations, speak with confidence, and connect in a faster way.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFB8C5CB),
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          _PrimaryCtaButton(
            label: 'CONTINUE',
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _TopBrandBar extends StatelessWidget {
  const _TopBrandBar();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'VAANI',
      style: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.8,
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final String message;

  const _SpeechBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF151E23),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFF33434C),
              width: 2.5,
            ),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF4F8F1),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        ClipPath(
          clipper: _SpeechTailClipper(),
          child: Container(
            width: 44,
            height: 34,
            color: const Color(0xFF33434C),
            padding: const EdgeInsets.only(top: 2),
            child: ClipPath(
              clipper: _SpeechTailInnerClipper(),
              child: Container(color: const Color(0xFF151E23)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeechTailClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.1, 0);
    path.lineTo(size.width * 0.9, 0);
    path.lineTo(size.width * 0.5, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SpeechTailInnerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.16, 0);
    path.lineTo(size.width * 0.84, 0);
    path.lineTo(size.width * 0.5, size.height * 0.92);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _MascotHero extends StatelessWidget {
  final double size;

  const _MascotHero({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 40,
      height: size + 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: size * 0.72,
              height: size * 0.22,
              decoration: BoxDecoration(
                color: const Color(0xFF2B3439),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Container(
            width: size + 12,
            height: size + 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF263238),
                width: 2,
              ),
            ),
          ),
          Container(
            width: size * 0.84,
            height: size * 0.84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF182227),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x773AE374),
                  blurRadius: 40,
                  spreadRadius: -6,
                  offset: Offset(0, 10),
                ),
              ],
            ),
          ),
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF202B30),
              border: Border.all(
                color: const Color(0xFF8EE62A),
                width: 6,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/Logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryCtaButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 74,
      child: Stack(
        children: [
          Positioned.fill(
            top: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF5BAA1B),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Positioned.fill(
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF95DE28),
                foregroundColor: const Color(0xFF13210B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryCtaButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 74,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF95DE28),
          side: const BorderSide(
            color: Color(0xFF33434C),
            width: 2.5,
          ),
          backgroundColor: const Color(0xFF11181C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int currentPage;

  const _PageDots({required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isActive ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF95DE28)
                : const Color(0xFF33434C),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
