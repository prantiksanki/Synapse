import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/detection_provider.dart';
import '../widgets/camera_preview.dart';
import '../widgets/gesture_display.dart';
import '../widgets/hand_overlay_painter.dart';
import '../widgets/sign_image_display.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeWithPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<DetectionProvider>();

    if (state == AppLifecycleState.inactive) {
      provider.stopDetection();
    } else if (state == AppLifecycleState.resumed) {
      if (provider.isInitialized) {
        provider.startDetection();
      }
    }
  }

  Future<void> _initializeWithPermission() async {
    if (!mounted) return;

    final provider = context.read<DetectionProvider>();
    if (!provider.isPlatformSupported) {
      await provider.initialize();
      return;
    }

    final statuses =
        await [Permission.camera, Permission.microphone].request();
    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    if (cameraGranted) {
      if (mounted) {
        await provider.initialize();
        if (provider.isInitialized) {
          await provider.startDetection();
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera permission is required for sign language detection',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (!micGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone denied — speech mode will be unavailable'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(AppConfig.appTitle),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          Consumer<DetectionProvider>(
            builder: (context, provider, _) {
              return IconButton(
                icon: Icon(
                  provider.isDetecting ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (provider.isDetecting) {
                    provider.stopDetection();
                  } else if (provider.isInitialized) {
                    provider.startDetection();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<DetectionProvider>(
        builder: (context, provider, _) {
          return _buildBody(provider);
        },
      ),
    );
  }

  Widget _buildBody(DetectionProvider provider) {
    switch (provider.state) {
      case DetectionState.uninitialized:
      case DetectionState.initializing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Initializing...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        );

      case DetectionState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  provider.isPlatformSupported
                      ? 'Error'
                      : 'Unsupported Platform',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (provider.isPlatformSupported)
                  ElevatedButton(
                    onPressed: _initializeWithPermission,
                    child: const Text('Retry'),
                  )
                else
                  Text(
                    kIsWeb
                        ? 'Switch to Android to use live camera detection.'
                        : 'Launch this build on Android to access the camera pipeline.',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        );

      case DetectionState.ready:
      case DetectionState.detecting:
        return _buildDetectionView(provider);
    }
  }

  Widget _buildDetectionView(DetectionProvider provider) {
    final controller = provider.cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview with hand overlay
        CameraPreviewWidget(
          controller: controller,
          overlay: HandOverlayWidget(
            landmarks: provider.currentLandmarks,
            previewSize: controller.value.previewSize ?? const Size(640, 480),
            isFrontCamera:
                controller.description.lensDirection ==
                CameraLensDirection.front,
            sensorOrientation: controller.description.sensorOrientation,
          ),
        ),

        // Bottom panel — switches between gesture display and sign image display
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: provider.appMode == AppMode.gestureMode
                ? GestureDisplay(
                    result: provider.currentGesture,
                    fps: provider.fps,
                    wordBufferState: provider.wordBufferState,
                    generationResult: provider.generationResult,
                    grammarStatus: provider.grammarStatus,
                    grammarLoadError: provider.grammarStatusMessage,
                    hasHandDetected: provider.currentLandmarks != null,
                    isGeneratingSentence: provider.isGeneratingSentence,
                    onSpeak: provider.generationResult.hasSentence
                        ? provider.speakLatestSentence
                        : null,
                    onSend: provider.wordBufferState.activeTokens.isNotEmpty
                        ? provider.forceGenerate
                        : null,
                  )
                : SignImageDisplay(
                    segments: provider.signImageSegments,
                    rawSpeechText: provider.rawSpeechText,
                    compressedKeywords: provider.compressedKeywords,
                    listenStatus: provider.speechListenStatus,
                    isProcessing: provider.isProcessingSpeech,
                  ),
          ),
        ),

        // Top status badges
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: provider.appMode == AppMode.speechMode
                        ? Colors.blue.withValues(alpha: 0.85)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        provider.appMode == AppMode.speechMode
                            ? Icons.mic
                            : Icons.sign_language,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        provider.appMode == AppMode.speechMode
                            ? 'Speech Mode'
                            : 'Gesture Mode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!provider.isDetecting) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Detection paused',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
