import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/webrtc_provider.dart';
import '../screens/caller_home_screen.dart';
import '../screens/detection_screen.dart';
import '../screens/model_download_screen.dart';
import '../services/t5_model_downloader.dart';

/// Shown once on first launch.
/// User picks their role (Disabled Person or Normal Person) and sets a username.
/// Saves role + username to SharedPreferences, then navigates to the correct home.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _usernameCtrl = TextEditingController();
  String? _errorText;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectRole(String role) async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _errorText = 'Please enter a username first.');
      return;
    }
    if (username.contains(' ')) {
      setState(() => _errorText = 'Username must not contain spaces.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webrtc_username', username);
    await prefs.setString('user_role', role);
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;

    // Connect WebRTC with chosen username + role
    context.read<WebRtcProvider>().connectWithRole(username, role);

    if (role == 'caller') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CallerHomeScreen()),
      );
    } else {
      // deaf — check if T5 models are downloaded
      final modelsReady = await T5ModelDownloader().allModelsDownloaded();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => modelsReady
              ? const DetectionScreen()
              : const ModelDownloadScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Logo / title
              const Icon(Icons.sign_language, size: 72, color: Color(0xFF8B5CF6)),
              const SizedBox(height: 16),
              const Text(
                'SYNAPSE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bridging communication gaps',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),

              const SizedBox(height: 48),

              // Question
              const Text(
                'Who are you?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This helps us give you the right experience.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Username field
              TextField(
                controller: _usernameCtrl,
                enabled: !_isLoading,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Your username',
                  labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                  hintText: 'e.g. prantik_1',
                  hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF8B5CF6)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  errorText: _errorText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                  ),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),

              const SizedBox(height: 28),

              // Role cards
              _RoleCard(
                emoji: '🤟',
                title: 'Disabled Person',
                subtitle: 'Full features: sign language detection,\nspeech translation, calling & more.',
                color: const Color(0xFF8B5CF6),
                isLoading: _isLoading,
                onTap: () => _selectRole('deaf'),
              ),

              const SizedBox(height: 16),

              _RoleCard(
                emoji: '📞',
                title: 'Normal Person',
                subtitle: 'Audio & video calling only.\nCall any SYNAPSE user directly.',
                color: const Color(0xFF06B6D4),
                isLoading: _isLoading,
                onTap: () => _selectRole('caller'),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
