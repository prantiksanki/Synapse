import 'dart:async';
import 'package:flutter/material.dart';
import 'detection_screen.dart';

/// Full-screen welcome splash shown after the grammar model finishes downloading.
/// Displays Welcome.gif on a black background for 5 seconds, then replaces
/// itself with DetectionScreen.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), _goHome);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DetectionScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _goHome,
        child: SizedBox.expand(
          child: Image.asset(
            'assets/Welcome.gif',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
