import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'providers/call_bridge_provider.dart';
import 'providers/detection_provider.dart';
import 'providers/webrtc_provider.dart';
import 'screens/caller_home_screen.dart';
import 'screens/detection_screen.dart';
import 'screens/model_download_screen.dart';
import 'screens/landing_screen.dart';
import 'services/hardware_service.dart';
import 'services/sign_image_service.dart';
import 'services/t5_model_downloader.dart';
import 'widgets/watch_sign_overlay.dart';

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final service = SignImageService();
  await service.initialize();
  runApp(WatchSignOverlayApp(signImageService: service));
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

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
    // First ever launch → landing page → onboarding
    if (!onboardingDone) return const LandingScreen();
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
        // HardwareService is created once and shared via Provider.
        Provider<HardwareService>(
          create: (_) => HardwareService()..connect(),
          dispose: (_, hw) => hw.dispose(),
        ),
        // DetectionProvider is created after HardwareService so we can wire
        // Pi camera frames directly into the landmark pipeline.
        ChangeNotifierProxyProvider<HardwareService, DetectionProvider>(
          create: (ctx) {
            final detection = DetectionProvider();
            detection.attachHardware(ctx.read<HardwareService>());
            return detection;
          },
          update: (ctx, hw, detection) {
            final d = detection ?? DetectionProvider();
            d.attachHardware(hw);
            return d;
          },
        ),
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
          fontFamily: GoogleFonts.nunito().fontFamily,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConfig.obPrimaryDark,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: AppConfig.obBackground,
          canvasColor: AppConfig.obBackground,
          cardColor: AppConfig.obCard,
          dividerColor: AppConfig.obBorder,
          textTheme: GoogleFonts.nunitoTextTheme().copyWith(
            displayLarge: GoogleFonts.nunito(
              fontWeight: FontWeight.w900,
              color: AppConfig.obTextPrimary,
            ),
            displayMedium: GoogleFonts.nunito(
              fontWeight: FontWeight.w900,
              color: AppConfig.obTextPrimary,
            ),
            displaySmall: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: AppConfig.obTextPrimary,
            ),
            headlineLarge: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: AppConfig.obTextPrimary,
            ),
            headlineMedium: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: AppConfig.obTextPrimary,
            ),
            headlineSmall: GoogleFonts.nunito(
              fontWeight: FontWeight.w700,
              color: AppConfig.obTextPrimary,
            ),
            titleLarge: GoogleFonts.nunito(
              fontWeight: FontWeight.w700,
              color: AppConfig.obTextPrimary,
            ),
            titleMedium: GoogleFonts.nunito(
              fontWeight: FontWeight.w700,
              color: AppConfig.obTextPrimary,
            ),
            titleSmall: GoogleFonts.nunito(
              fontWeight: FontWeight.w600,
              color: AppConfig.obTextPrimary,
            ),
            bodyLarge: GoogleFonts.nunito(
              fontWeight: FontWeight.w600,
              color: AppConfig.obTextPrimary,
            ),
            bodyMedium: GoogleFonts.nunito(
              fontWeight: FontWeight.w600,
              color: AppConfig.obTextPrimary,
            ),
            bodySmall: GoogleFonts.nunito(
              fontWeight: FontWeight.w600,
              color: AppConfig.obTextSecondary,
            ),
            labelLarge: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: AppConfig.obTextPrimary,
            ),
            labelMedium: GoogleFonts.nunito(
              fontWeight: FontWeight.w700,
              color: AppConfig.obTextSecondary,
            ),
            labelSmall: GoogleFonts.nunito(
              fontWeight: FontWeight.w700,
              color: AppConfig.obTextSecondary,
            ),
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: AppConfig.obTextPrimary,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            centerTitle: true,
            titleTextStyle: GoogleFonts.nunito(
              color: AppConfig.obTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          iconTheme: const IconThemeData(
            color: AppConfig.obTextPrimary,
            size: 22,
          ),
          cardTheme: CardThemeData(
            color: AppConfig.obCard,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppConfig.obBorder, width: 2),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConfig.obPrimary,
              side: const BorderSide(color: AppConfig.obBorder, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              textStyle: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.obPrimary,
              foregroundColor: const Color(0xFF13210B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              textStyle: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppConfig.obPrimary,
              textStyle: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppConfig.obCard,
            hintStyle: GoogleFonts.nunito(
              color: AppConfig.obTextSecondary,
              fontWeight: FontWeight.w700,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: AppConfig.obBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: AppConfig.obBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: AppConfig.obPrimary, width: 1.6),
            ),
          ),
          useMaterial3: true,
        ),
        home: _resolveHome(),
      ),
    );
  }
}