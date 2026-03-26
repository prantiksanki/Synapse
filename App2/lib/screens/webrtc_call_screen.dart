import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/webrtc_provider.dart';
import '../providers/detection_provider.dart';
import '../widgets/gesture_display.dart';
import '../widgets/sign_image_display.dart';

/// Full-screen UI shown during an active WebRTC call.
/// Reuses existing GestureDisplay and SignImageDisplay widgets — no modifications needed.
class WebRtcCallScreen extends StatelessWidget {
  const WebRtcCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<WebRtcProvider, DetectionProvider>(
      builder: (context, webRtc, detection, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Remote video (caller) — full-screen background ──────────
              RTCVideoView(
                webRtc.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                placeholderBuilder: (_) => Container(
                  color: const Color(0xFF0D0D1A),
                  child: const Center(
                    child: Icon(Icons.person, size: 80, color: Colors.grey),
                  ),
                ),
              ),

              // ── Local camera (for sign detection) — top-right PiP ──────
              Positioned(
                top: 48,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 110,
                    height: 150,
                    child: RTCVideoView(
                      webRtc.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      placeholderBuilder: (_) => Container(color: Colors.black54),
                    ),
                  ),
                ),
              ),

              // ── Top bar: caller info + status ───────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 130, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          webRtc.callerUsername ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                        const Text(
                          'Active call',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Bottom panel: sign detection + caller transcript ─────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withAlpha(230),
                        Colors.black.withAlpha(100),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Sign detection panel (reuses existing widget)
                          GestureDisplay(
                            result: detection.currentGesture,
                            fps: detection.fps,
                            wordBufferState: detection.wordBufferState,
                            generationResult: detection.generationResult,
                            grammarStatus: detection.grammarStatus,
                            hasHandDetected: detection.handIsPresent,
                            isGeneratingSentence: detection.isGeneratingSentence,
                          ),
                          const SizedBox(height: 8),
                          // Caller speech → sign images (reuses existing widget)
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 6),
                          const Text(
                            'CALLER SAYS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SignImageDisplay(
                            segments: detection.signImageSegments,
                            rawSpeechText: detection.rawSpeechText,
                            compressedKeywords: detection.compressedKeywords,
                            listenStatus: detection.speechListenStatus,
                            isProcessing: detection.isProcessingSpeech,
                          ),
                          const SizedBox(height: 12),
                          // End call button
                          Center(
                            child: FloatingActionButton(
                              heroTag: 'webrtc_end',
                              mini: false,
                              onPressed: () {
                                webRtc.endCall();
                                Navigator.of(context).pop();
                              },
                              backgroundColor: Colors.red,
                              child: const Icon(Icons.call_end),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
