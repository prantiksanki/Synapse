import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../providers/call_bridge_provider.dart';
import '../providers/detection_provider.dart';
import '../providers/webrtc_provider.dart';
import '../screens/deaf_call_screen.dart';
import '../screens/emergency_screen.dart';
import '../screens/shop_screen.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tutorial_screen.dart';
import '../screens/webrtc_call_screen.dart';
import '../services/call_bridge_service.dart';
import '../widgets/gesture_display.dart';
import '../widgets/liquid_glass_navbar.dart';
import '../widgets/sign_image_display.dart';
import '../widgets/tour_guide.dart';

enum TranslatorHomeMode { voiceToSign, signToText }

const _kModePrefKey = 'home_mode';
const _kSurface = Color(0xFF0F1A12);
const _kCard = Color(0xFF16241C);
const _kPrimary = Color(0xFF95DE28);
const _kPrimaryDark = Color(0xFF6DBA1C);
const _kAccent = Color(0xFF33434A);
const _kSuccess = Color(0xFF22C55E);
const _kMuted = Color(0xFF92A395);
const _kTextPrimary = Color(0xFFF1F7E8);
const _kBorder = Color(0xFF2A3E30);

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with WidgetsBindingObserver {
  bool _incomingRouteOpen = false;
  bool _callRouteOpen = false;
  bool _modeReady = false;
  String? _localErrorMessage;
  TranslatorHomeMode _mode = TranslatorHomeMode.signToText;
  NavTab _currentTab = NavTab.home;

  // Volume-up double-press tracking
  DateTime? _lastVolumeUpPress;

  // Tour guide keys — one per spotlighted component
  final _tourHeaderKey   = GlobalKey();
  final _tourToggleKey   = GlobalKey();
  final _tourContentKey  = GlobalKey();
  final _tourNavBarKey   = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreSavedMode();
      if (!mounted) return;
      await _initializeWithPermission();
      if (!mounted) return;
      _connectWebRtc();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      final now = DateTime.now();
      if (_lastVolumeUpPress != null &&
          now.difference(_lastVolumeUpPress!) < const Duration(milliseconds: 600)) {
        _lastVolumeUpPress = null;
        _toggleMode();
        return true; // consumed
      }
      _lastVolumeUpPress = now;
    }
    return false;
  }

  void _toggleMode() {
    final next = _mode == TranslatorHomeMode.voiceToSign
        ? TranslatorHomeMode.signToText
        : TranslatorHomeMode.voiceToSign;
    _switchMode(next);
    if (!mounted) return;
    final label =
        next == TranslatorHomeMode.voiceToSign ? 'Voice → Sign' : 'Sign → Text/Voice';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mode switched: $label',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _kPrimaryDark,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<DetectionProvider>();

    if (state == AppLifecycleState.paused) {
      if (!_isCallActive()) {
        provider.stopDetection();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_mode == TranslatorHomeMode.signToText && provider.isInitialized) {
        provider.startDetection();
      }
      // Persist overlay permission if the user just granted it from Settings
      if (defaultTargetPlatform == TargetPlatform.android) {
        _persistOverlayPermissionIfGranted();
      }
    }
  }

  Future<void> _persistOverlayPermissionIfGranted() async {
    const overlayPrefKey = 'overlay_permission_granted';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(overlayPrefKey) ?? false) return; // already stored
    const platform = MethodChannel('synapse/call_control');
    final isGranted =
        await platform.invokeMethod<bool>('isOverlayPermissionGranted') ?? false;
    if (isGranted) {
      await prefs.setBool(overlayPrefKey, true);
    }
  }

  Future<void> _restoreSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kModePrefKey);
    final restored = TranslatorHomeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => TranslatorHomeMode.signToText,
    );
    if (!mounted) return;
    setState(() {
      _mode = restored;
      _modeReady = true;
    });
  }

  Future<void> _persistMode(TranslatorHomeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModePrefKey, mode.name);
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
      if (mounted && _localErrorMessage != null) {
        setState(() => _localErrorMessage = null);
      }
      await provider.initialize();
      if (provider.isInitialized && _mode == TranslatorHomeMode.signToText) {
        await provider.startDetection();
      }
    } else if (mounted) {
      setState(() {
        _localErrorMessage =
            'Camera permission is required for sign language detection.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is required for sign language detection.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!micGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone denied - voice mode will be limited.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      const platform = MethodChannel('synapse/call_control');
      const overlayPrefKey = 'overlay_permission_granted';
      final prefs = await SharedPreferences.getInstance();
      final overlayAlreadyGranted = prefs.getBool(overlayPrefKey) ?? false;

      if (!overlayAlreadyGranted) {
        // Ask native side — it only opens Settings if permission is not yet granted
        await platform.invokeMethod('requestOverlayPermission');
        // Ask native whether permission is now granted so we can persist the result
        final isGranted =
            await platform.invokeMethod<bool>('isOverlayPermissionGranted') ??
                false;
        if (isGranted) {
          await prefs.setBool(overlayPrefKey, true);
        }
      }

      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted && mounted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    }
  }

  Future<void> _connectWebRtc() async {
    if (!mounted) return;
    context.read<WebRtcProvider>().connectFromPrefs();
  }

  void _onNavTabChanged(NavTab tab) {
    setState(() => _currentTab = tab);
    if (tab == NavTab.call) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const DeafCallScreen()))
          .whenComplete(() {
        if (mounted) setState(() => _currentTab = NavTab.home);
      });
    } else if (tab == NavTab.emergency) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EmergencyScreen()))
          .whenComplete(() {
        if (mounted) setState(() => _currentTab = NavTab.home);
      });
    } else if (tab == NavTab.settings) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
          .whenComplete(() {
        if (mounted) setState(() => _currentTab = NavTab.home);
      });
    } else if (tab == NavTab.tutorial) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TutorialScreen()))
          .whenComplete(() {
        if (mounted) setState(() => _currentTab = NavTab.home);
      });
    } else if (tab == NavTab.shop) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ShopScreen()))
          .whenComplete(() {
        if (mounted) setState(() => _currentTab = NavTab.home);
      });
    }
  }

  bool _isCallActive() {
    final callProvider = context.read<CallBridgeProvider>();
    return callProvider.callState == PhoneCallState.active ||
        callProvider.callState == PhoneCallState.ringing;
  }

  Future<void> _switchMode(TranslatorHomeMode nextMode) async {
    if (_mode == nextMode) return;

    HapticFeedback.lightImpact();
    setState(() => _mode = nextMode);
    await _persistMode(nextMode);

    if (!mounted) return;
    final provider = context.read<DetectionProvider>();
    if (nextMode == TranslatorHomeMode.voiceToSign && !_isCallActive()) {
      await provider.stopDetection();
    } else if (nextMode == TranslatorHomeMode.signToText && provider.isInitialized) {
      await provider.startDetection();
    }
  }

  void _showIncomingCallDialog(BuildContext context) {
    if (_incomingRouteOpen) return;
    _incomingRouteOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const IncomingCallScreen()))
        .whenComplete(() => _incomingRouteOpen = false);
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              color: _kPrimary,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Preparing translator...',
            style: TextStyle(
              color: _kMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context, {
    required String message,
    required bool canRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              canRetry ? 'Something went wrong' : 'Unsupported platform',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (canRetry)
              ElevatedButton(
                onPressed: _initializeWithPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslatorShell(
    BuildContext context,
    DetectionProvider provider,
    WebRtcProvider webRtc,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF142218), Color(0xFF0F1A12)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: _tourHeaderKey,
                  child: _TranslatorHeader(
                    isConnected: webRtc.isConnected,
                    mode: _mode,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  key: _tourToggleKey,
                  child: _ModeToggle(
                    mode: _mode,
                    onChanged: _switchMode,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SizedBox(
                    key: _tourContentKey,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(curved),
                            child: child,
                          ),
                        );
                      },
                      child: _mode == TranslatorHomeMode.voiceToSign
                          ? KeyedSubtree(
                              key: const ValueKey('voiceToSign'),
                              child: _VoiceToSignContent(provider: provider),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('signToText'),
                              child: _SignToTextContent(provider: provider),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebRtcProvider>(
      builder: (context, webRtc, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (webRtc.status == WebRtcCallStatus.ringing &&
              !_incomingRouteOpen &&
              !_callRouteOpen) {
            _showIncomingCallDialog(context);
          } else if (webRtc.status == WebRtcCallStatus.active && !_callRouteOpen) {
            _callRouteOpen = true;
            if (_incomingRouteOpen) {
              Navigator.of(context).pop();
              _incomingRouteOpen = false;
            }
            Navigator.of(context)
                .push(
                  MaterialPageRoute(builder: (_) => const WebRtcCallScreen()),
                )
                .whenComplete(() => _callRouteOpen = false);
          } else if (webRtc.status == WebRtcCallStatus.idle ||
              webRtc.status == WebRtcCallStatus.ended) {
            _callRouteOpen = false;
          }
        });

        final scaffold = Scaffold(
          backgroundColor: _kSurface,
          bottomNavigationBar: SizedBox(
            key: _tourNavBarKey,
            child: LiquidGlassNavBar(
              currentTab: _currentTab,
              onTabChanged: _onNavTabChanged,
            ),
          ),
          body: Consumer<DetectionProvider>(
            builder: (context, provider, __) {
              if (_localErrorMessage != null &&
                  provider.state == DetectionState.uninitialized) {
                return _buildErrorState(
                  context,
                  message: _localErrorMessage!,
                  canRetry: true,
                );
              }

              if (!_modeReady ||
                  provider.state == DetectionState.uninitialized ||
                  provider.state == DetectionState.initializing) {
                return _buildLoadingState();
              }

              if (provider.state == DetectionState.error) {
                return _buildErrorState(
                  context,
                  message: provider.errorMessage ?? 'Unknown error',
                  canRetry: provider.isPlatformSupported,
                );
              }

              return _buildTranslatorShell(context, provider, webRtc);
            },
          ),
        );

        return TourGuide(
          steps: [
            TourStep(
              targetKey: null,
              message: "Welcome to VAANI!\nLet me give you a quick tour of the app.",
              spotPadding: 0,
            ),
            TourStep(
              targetKey: _tourHeaderKey,
              message: "This is the header.\nIt shows the app name and your online or offline connection status.",
            ),
            TourStep(
              targetKey: _tourToggleKey,
              message: "This toggle switches your mode.\nVoice to Sign: speak and see signs.\nSign to Text: show signs, get text and voice.",
              spotPadding: 10,
            ),
            TourStep(
              targetKey: _tourContentKey,
              message: "This is the main panel.\nIn Sign to Text mode, your camera detects hand signs here in real time.",
              spotPadding: 8,
            ),
            TourStep(
              targetKey: _tourNavBarKey,
              message: "Use the bottom navbar to navigate.\nCall, Emergency, Tutorial, Shop, and Settings are all here.",
              spotPadding: 6,
            ),
            TourStep(
              targetKey: null,
              message: "You are all set!\nTip: double-press Volume Up anytime to quickly switch modes.",
              spotPadding: 0,
            ),
          ],
          child: scaffold,
        );
      },
    );
  }
}

class _TranslatorHeader extends StatelessWidget {
  final bool isConnected;
  final TranslatorHomeMode mode;

  const _TranslatorHeader({
    required this.isConnected,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final modeLabel = mode == TranslatorHomeMode.voiceToSign
        ? 'Voice to Sign'
        : 'Sign to Text/Voice';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                AppConfig.appTitle,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                modeLabel,
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF16241C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: isConnected ? _kSuccess : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Text(
                isConnected ? 'Online' : 'Offline',
                style: TextStyle(
                  color: isConnected ? _kSuccess : Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final TranslatorHomeMode mode;
  final ValueChanged<TranslatorHomeMode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF16241C),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            alignment: mode == TranslatorHomeMode.signToText
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kPrimary, _kPrimaryDark],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ModeToggleOption(
                  selected: mode == TranslatorHomeMode.voiceToSign,
                  icon: Icons.mic_rounded,
                  label: 'Voice -> Sign',
                  onTap: () => onChanged(TranslatorHomeMode.voiceToSign),
                ),
              ),
              Expanded(
                child: _ModeToggleOption(
                  selected: mode == TranslatorHomeMode.signToText,
                  icon: Icons.sign_language_rounded,
                  label: 'Sign -> Text/Voice',
                  onTap: () => onChanged(TranslatorHomeMode.signToText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeToggleOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModeToggleOption({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? const Color(0xFF11181C) : _kTextPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceToSignContent extends StatelessWidget {
  final DetectionProvider provider;

  const _VoiceToSignContent({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TranslatorCard(
          label: 'Recognized Text',
          icon: Icons.notes_rounded,
          accent: _kAccent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Text(
              provider.rawSpeechText.trim().isEmpty
                  ? 'Your spoken words will appear here.'
                  : provider.rawSpeechText.trim(),
              style: TextStyle(
                color: provider.rawSpeechText.trim().isEmpty
                    ? _kMuted
                    : _kTextPrimary,
                fontSize: 15,
                height: 1.45,
                fontWeight: provider.rawSpeechText.trim().isEmpty
                    ? FontWeight.w500
                    : FontWeight.w600,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _TranslatorCard(
            label: 'Sign Language Sequence',
            icon: Icons.view_carousel_rounded,
            accent: _kPrimary,
            child: SignImageDisplay(
              segments: provider.signImageSegments,
              listenStatus: provider.speechListenStatus,
              isProcessing: provider.isProcessingSpeech,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignToTextContent extends StatelessWidget {
  final DetectionProvider provider;

  const _SignToTextContent({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: _HandSignalOrb(hasHand: provider.currentLandmarks != null),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _TranslatorCard(
            label: 'Model Result',
            icon: Icons.auto_awesome_rounded,
            accent: _kAccent,
            child: GestureDisplay(
              result: provider.currentGesture,
              fps: provider.fps,
              wordBufferState: provider.wordBufferState,
              generationResult: provider.generationResult,
              grammarStatus: provider.grammarStatus,
              grammarLoadError: provider.grammarStatusMessage,
              hasHandDetected: provider.currentLandmarks != null,
              isGeneratingSentence: provider.isGeneratingSentence,
              signImageBytes: provider.currentSignImage,
              onSpeak: provider.generationResult.hasSentence
                  ? provider.speakLatestSentence
                  : null,
              onSend: provider.wordBufferState.activeTokens.isNotEmpty
                  ? provider.forceGenerate
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _TranslatorCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _TranslatorCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _kBorder, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
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

class _HandSignalOrb extends StatefulWidget {
  final bool hasHand;

  const _HandSignalOrb({required this.hasHand});

  @override
  State<_HandSignalOrb> createState() => _HandSignalOrbState();
}

class _HandSignalOrbState extends State<_HandSignalOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.hasHand) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _HandSignalOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasHand && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.hasHand && _glowController.isAnimating) {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.hasHand ? _kPrimary : const Color(0xFF6D7A70);
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: widget.hasHand ? 0.24 : 0.15),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            boxShadow: widget.hasHand
                ? [
                    BoxShadow(
                      color: color.withValues(
                        alpha: 0.34 + (_glowController.value * 0.26),
                      ),
                      blurRadius: 26,
                      spreadRadius: 2.5,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.back_hand_outlined, color: color, size: 32),
              const SizedBox(height: 6),
              Text(
                widget.hasHand ? 'HAND ON' : 'HAND OFF',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
