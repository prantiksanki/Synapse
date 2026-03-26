import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'providers/call_bridge_provider.dart';
import 'providers/detection_provider.dart';
import 'providers/webrtc_provider.dart';
import 'screens/caller_home_screen.dart';
import 'screens/detection_screen.dart';
import 'screens/model_download_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/t5_model_downloader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final String? role = prefs.getString('user_role');

  // Only check model download status for deaf role (caller doesn't need T5)
  final bool modelsReady = (role == 'deaf' || !onboardingDone)
      ? await T5ModelDownloader().allModelsDownloaded()
      : true;

  runApp(SignLanguageApp(
    onboardingDone: onboardingDone,
    role: role,
    modelsReady: modelsReady,
  ));
}

class SignLanguageApp extends StatelessWidget {
  final bool onboardingDone;
  final String? role;
  final bool modelsReady;

  const SignLanguageApp({
    super.key,
    required this.onboardingDone,
    required this.role,
    required this.modelsReady,
  });

  Widget _resolveHome() {
    // First ever launch → onboarding
    if (!onboardingDone) return const OnboardingScreen();
    // Normal Person → calling-only UI
    if (role == 'caller') return const CallerHomeScreen();
    // Disabled Person — check T5 models
    if (!modelsReady) return const ModelDownloadScreen();
    return const DetectionScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DetectionProvider()),
        ChangeNotifierProxyProvider<DetectionProvider, CallBridgeProvider>(
          create: (_) => CallBridgeProvider(),
          update: (_, detection, bridge) {
            final b = bridge ?? CallBridgeProvider();
            b.attach(detection);
            return b;
          },
        ),
        ChangeNotifierProxyProvider<DetectionProvider, WebRtcProvider>(
          create: (_) => WebRtcProvider(),
          update: (_, detection, webRtc) {
            final w = webRtc ?? WebRtcProvider();
            w.setDetectionProvider(detection);
            return w;
          },
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B5CF6),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF0EEFF),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: Color(0xFF1A1A2E),
            elevation: 0,
            titleTextStyle: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          useMaterial3: true,
        ),
        home: _resolveHome(),
      ),
    );
  }
}
