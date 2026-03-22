import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'providers/detection_provider.dart';
import 'screens/detection_screen.dart';
import 'screens/model_download_screen.dart';
import 'services/t5_model_downloader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Check whether T5 models are already downloaded so we can pick the right
  // start screen before the widget tree is built.
  final bool modelsReady = await T5ModelDownloader().allModelsDownloaded();

  runApp(SignLanguageApp(modelsReady: modelsReady));
}

class SignLanguageApp extends StatelessWidget {
  final bool modelsReady;

  const SignLanguageApp({super.key, required this.modelsReady});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DetectionProvider(),
      child: MaterialApp(
        title: AppConfig.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        // First launch → download screen; subsequent launches → detection directly.
        home: modelsReady
            ? const DetectionScreen()
            : const ModelDownloadScreen(),
      ),
    );
  }
}
