import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_bridge_provider.dart';
import '../providers/detection_provider.dart';
import '../services/call_bridge_service.dart';
import '../widgets/camera_preview.dart';
import '../widgets/gesture_display.dart';
import '../widgets/hand_overlay_painter.dart';
import '../widgets/sign_image_display.dart';

/// Full-screen overlay shown while a phone call is active.
///
/// Top half  — camera + hand landmark overlay (user signs here).
/// Bottom half — two panels:
///   • "You said" — last sentence spoken into the call via TTS.
///   • "Caller says" — caller's voice transcribed by STT, shown as sign images.
class CallOverlayScreen extends StatelessWidget {
  const CallOverlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EEFF),
        foregroundColor: const Color(0xFF1A1A2E),
        title: Consumer<CallBridgeProvider>(
          builder: (_, provider, __) {
            final number = provider.callerNumber;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Call Bridge',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (number.isNotEmpty)
                  Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
              ],
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to detection',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer2<DetectionProvider, CallBridgeProvider>(
        builder: (context, detection, callProvider, _) {
          return Column(
            children: [
              // ── Call state banner ──────────────────────────────────────
              _CallStateBadge(
                state: callProvider.callState,
                isTtsSpeaking: callProvider.isTtsSpeaking,
              ),

              // ── Camera + hand overlay ──────────────────────────────────
              Expanded(
                flex: 5,
                child: _CameraPanel(detection: detection),
              ),

              // ── Divider ────────────────────────────────────────────────
              const Divider(height: 1, color: Color(0xFFE5E7EB)),

              // ── Gesture display (what you are signing) ─────────────────
              Expanded(
                flex: 3,
                child: _YouSaidPanel(
                  detection: detection,
                  lastSpoken: callProvider.lastSpoken,
                ),
              ),

              // ── Divider ────────────────────────────────────────────────
              const Divider(height: 1, color: Color(0xFFE5E7EB)),

              // ── Caller transcript as sign images ───────────────────────
              Expanded(
                flex: 4,
                child: _CallerPanel(
                  detection: detection,
                  transcript: callProvider.callerTranscript,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _CallStateBadge extends StatelessWidget {
  final PhoneCallState state;
  final bool isTtsSpeaking;

  const _CallStateBadge({required this.state, required this.isTtsSpeaking});

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      PhoneCallState.ringing => 'Incoming call…',
      PhoneCallState.active  => isTtsSpeaking ? 'Speaking to caller…' : 'Call active — sign to speak',
      PhoneCallState.ended   => 'Call ended',
      PhoneCallState.idle    => 'No active call',
    };
    final color = switch (state) {
      PhoneCallState.ringing => const Color(0xFFF59E0B),
      PhoneCallState.active  => isTtsSpeaking ? const Color(0xFF60A5FA) : const Color(0xFF34D399),
      _                      => const Color(0xFF9CA3AF),
    };

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  final DetectionProvider detection;

  const _CameraPanel({required this.detection});

  @override
  Widget build(BuildContext context) {
    final controller = detection.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
      );
    }

    return CameraPreviewWidget(
      controller: controller,
      overlay: HandOverlayWidget(
        landmarks: detection.currentLandmarks,
        previewSize: controller.value.previewSize ?? const Size(640, 480),
        isFrontCamera:
            controller.description.lensDirection == CameraLensDirection.front,
        sensorOrientation: controller.description.sensorOrientation,
      ),
    );
  }
}

class _YouSaidPanel extends StatelessWidget {
  final DetectionProvider detection;
  final String lastSpoken;

  const _YouSaidPanel({required this.detection, required this.lastSpoken});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F7FF),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sign_language, color: Color(0xFF34D399), size: 14),
              const SizedBox(width: 6),
              const Text(
                'YOU (signing → caller hears)',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: GestureDisplay(
                result: detection.currentGesture,
                fps: detection.fps,
                wordBufferState: detection.wordBufferState,
                generationResult: detection.generationResult,
                grammarStatus: detection.grammarStatus,
                grammarLoadError: detection.grammarStatusMessage,
                hasHandDetected: detection.currentLandmarks != null,
                isGeneratingSentence: detection.isGeneratingSentence,
                onSpeak: detection.generationResult.hasSentence
                    ? detection.speakLatestSentence
                    : null,
                onSend: detection.wordBufferState.activeTokens.isNotEmpty
                    ? detection.forceGenerate
                    : null,
              ),
            ),
          ),
          if (lastSpoken.isNotEmpty) ...[
            const Divider(height: 8, color: Color(0xFFF3F4F6)),
            Text(
              'Last spoken: "$lastSpoken"',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _CallerPanel extends StatelessWidget {
  final DetectionProvider detection;
  final String transcript;

  const _CallerPanel({required this.detection, required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hearing, color: Color(0xFF60A5FA), size: 14),
              const SizedBox(width: 6),
              const Text(
                'CALLER SAYS (you see)',
                style: TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (transcript.isNotEmpty)
            Text(
              transcript,
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Expanded(
            child: detection.signImageSegments.isNotEmpty
                ? SignImageDisplay(
                    segments: detection.signImageSegments,
                    listenStatus: detection.speechListenStatus,
                    isProcessing: detection.isProcessingSpeech,
                  )
                : Center(
                    child: Text(
                      transcript.isEmpty
                          ? 'Listening to caller…'
                          : 'Processing…',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
