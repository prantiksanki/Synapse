import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/call_bridge_provider.dart';
import '../providers/detection_provider.dart';
import '../providers/webrtc_provider.dart';
import '../screens/webrtc_call_screen.dart';
import '../services/call_bridge_service.dart';
import '../widgets/camera_preview.dart';
import '../widgets/gesture_display.dart';
import '../widgets/hand_overlay_painter.dart';
import '../widgets/mode_status_bar.dart';
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
      _connectWebRtc();
    });
  }

  Future<void> _connectWebRtc() async {
    // Username and role are set during onboarding — just read and connect.
    if (!mounted) return;
    context.read<WebRtcProvider>().connectFromPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<DetectionProvider>();

    if (state == AppLifecycleState.paused) {
      // Keep detection running during active calls so sign language is captured
      final callProvider = context.read<CallBridgeProvider>();
      final callActive = callProvider.callState == PhoneCallState.active ||
          callProvider.callState == PhoneCallState.ringing;
      if (!callActive) provider.stopDetection();
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

    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.phone,
    ].request();
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

    // Request overlay permission so the floating call bubble can appear
    if (defaultTargetPlatform == TargetPlatform.android) {
      final platform = MethodChannel('synapse/call_control');
      await platform.invokeMethod('requestOverlayPermission');

      // Request battery optimization exemption so Android/MIUI doesn't kill
      // the foreground service when a call comes in while the app is in background.
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted && mounted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to WebRTC call state changes
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (webRtc.status == WebRtcCallStatus.ringing) {
            _showIncomingCallDialog(context, webRtc);
          } else if (webRtc.status == WebRtcCallStatus.active) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WebRtcCallScreen()),
            );
          }
        });
        return child!;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF0EEFF),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(AppConfig.appTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
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
      body: Consumer2<DetectionProvider, CallBridgeProvider>(
        builder: (ctx, provider, callProvider, _) => _buildBody(ctx, provider, callProvider),
      ),
    ),   // Scaffold
    );   // Consumer<WebRtcProvider>
  }

  void _showIncomingCallDialog(BuildContext context, WebRtcProvider webRtc) {
    // Avoid showing duplicate dialogs
    if (ModalRoute.of(context)?.isCurrent != true) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('${webRtc.callerUsername ?? 'Someone'} is calling…'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              webRtc.rejectCall();
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              webRtc.acceptCall();
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, DetectionProvider provider, CallBridgeProvider callProvider) {
    switch (provider.state) {
      case DetectionState.uninitialized:
      case DetectionState.initializing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF8B5CF6)),
              SizedBox(height: 16),
              Text('Initializing...', style: TextStyle(color: Color(0xFF4B5563))),
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
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 64),
                const SizedBox(height: 16),
                Text(
                  provider.isPlatformSupported
                      ? 'Error'
                      : 'Unsupported Platform',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: const Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Color(0xFF4B5563)),
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
                    style: const TextStyle(color: Color(0xFF6B7280)),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        );

      case DetectionState.ready:
      case DetectionState.detecting:
        return _buildDetectionView(context, provider, callProvider);
    }
  }

  Widget _buildDetectionView(BuildContext context, DetectionProvider provider, CallBridgeProvider callProvider) {
    final controller = provider.cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }

    final screenH = MediaQuery.of(context).size.height;
    final callIsActive = callProvider.callState == PhoneCallState.active ||
        callProvider.callState == PhoneCallState.ringing;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera layer ──────────────────────────────────────────────────────
        CameraPreviewWidget(
          controller: controller,
          overlay: HandOverlayWidget(
            landmarks: provider.currentLandmarks,
            previewSize: controller.value.previewSize ?? const Size(640, 480),
            isFrontCamera:
                controller.description.lensDirection == CameraLensDirection.front,
            sensorOrientation: controller.description.sensorOrientation,
          ),
        ),

        // ── Top overlay: ModeStatusBar + optional paused badge ────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: kToolbarHeight),
                ModeStatusBar(
                  dominantMode: provider.appMode,
                  sttIsListening: callIsActive
                      ? callProvider.isCallerSttListening
                      : provider.speechListenStatus == SpeechListenStatus.listening,
                  callIsActive: callIsActive,
                  isTtsSpeaking: callProvider.isTtsSpeaking,
                  callerNumber: callProvider.callerNumber,
                ),
                if (!provider.isDetecting) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Detection paused',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Bottom panels ─────────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenH * 0.62),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sign detection panel
                    _PanelShell(
                      label: 'SIGN DETECTION',
                      icon: Icons.sign_language,
                      headerColor: const Color(0xFF8B5CF6),
                      child: GestureDisplay(
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
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Voice to sign panel
                    _PanelShell(
                      label: 'VOICE TO SIGN',
                      icon: Icons.mic,
                      headerColor: const Color(0xFF60A5FA),
                      child: SignImageDisplay(
                        segments: provider.signImageSegments,
                        rawSpeechText: provider.rawSpeechText,
                        compressedKeywords: provider.compressedKeywords,
                        listenStatus: provider.speechListenStatus,
                        isProcessing: provider.isProcessingSpeech,
                      ),
                    ),
                    // Call panel — slides in when call is active/ringing
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                      child: callIsActive
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 6),
                                _PanelShell(
                                  label: 'CALL',
                                  icon: Icons.call,
                                  headerColor: callProvider.callState == PhoneCallState.active
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFFF59E0B),
                                  child: _CallPanelContent(
                                    callProvider: callProvider,
                                    provider: provider,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Panel shell widget ─────────────────────────────────────────────────────────

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.label,
    required this.icon,
    required this.headerColor,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Color headerColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: headerColor.withValues(alpha: 0.6), width: 2.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(
              children: [
                Icon(icon, color: headerColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ── Call panel content ─────────────────────────────────────────────────────────

class _CallPanelContent extends StatelessWidget {
  const _CallPanelContent({
    required this.callProvider,
    required this.provider,
  });

  final CallBridgeProvider callProvider;
  final DetectionProvider provider;

  @override
  Widget build(BuildContext context) {
    if (callProvider.callState == PhoneCallState.ringing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.ring_volume, color: Color(0xFFF59E0B), size: 16),
            const SizedBox(width: 8),
            Text(
              'Incoming call${callProvider.callerNumber.isNotEmpty ? ' from ${callProvider.callerNumber}' : ''}',
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Caller says
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          child: Text(
            'CALLER SAYS',
            style: TextStyle(
              color: const Color(0xFF9CA3AF),
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (callProvider.callerTranscript.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              callProvider.callerTranscript,
              style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 13),
            ),
          ),
        SignImageDisplay(
          segments: provider.signImageSegments,
          rawSpeechText: callProvider.callerTranscript,
          compressedKeywords: provider.compressedKeywords,
          listenStatus: callProvider.callerListenStatus,
          isProcessing: provider.isProcessingSpeech,
        ),
        const Divider(color: Color(0xFFF3F4F6), height: 1),
        // You signed
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
          child: Text(
            'YOU SIGNED',
            style: TextStyle(
              color: const Color(0xFF9CA3AF),
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  callProvider.lastSpoken.isEmpty
                      ? 'Sign language will be spoken to caller...'
                      : callProvider.lastSpoken,
                  style: TextStyle(
                    color: callProvider.lastSpoken.isEmpty
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF1A1A2E),
                    fontSize: 13,
                    fontStyle: callProvider.lastSpoken.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              if (callProvider.isTtsSpeaking) ...[
                const SizedBox(width: 8),
                const Icon(Icons.volume_up, color: Color(0xFF34D399), size: 16),
                const SizedBox(width: 4),
                const Text(
                  'Speaking...',
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
