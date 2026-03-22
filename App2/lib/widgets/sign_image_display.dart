import 'package:flutter/material.dart';
import '../services/sign_image_service.dart';

enum SpeechListenStatus { idle, listening, processing }

/// Bottom panel displayed when the app is in speech mode (no hand detected).
/// Shows the raw speech transcription, extracted keywords, and a horizontal
/// scrollable row of sign-language images for each character.
class SignImageDisplay extends StatelessWidget {
  final List<SignImageSegment> segments;
  final String rawSpeechText;
  final String compressedKeywords;
  final SpeechListenStatus listenStatus;
  final bool isProcessing;

  const SignImageDisplay({
    super.key,
    required this.segments,
    required this.rawSpeechText,
    required this.compressedKeywords,
    required this.listenStatus,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeIndicator(),
          const SizedBox(height: 8),
          _buildSpeechText(),
          const SizedBox(height: 8),
          _buildImageRow(),
        ],
      ),
    );
  }

  Widget _buildModeIndicator() {
    final isListening = listenStatus == SpeechListenStatus.listening;
    final isProcessingState = listenStatus == SpeechListenStatus.processing;

    final Color borderColor =
        isListening ? Colors.lightBlueAccent : Colors.white24;
    final Color bgColor =
        isListening ? Colors.blue.withValues(alpha: 0.3) : Colors.black54;

    String label;
    if (isProcessingState) {
      label = 'Processing...';
    } else if (isListening) {
      label = 'Listening...';
    } else {
      label = 'Show your hand to switch back to gesture mode';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isListening ? Icons.mic : Icons.mic_off,
            color: isListening ? Colors.lightBlueAccent : Colors.white54,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isListening ? Colors.lightBlueAccent : Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
          if (isProcessing || isProcessingState) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.lightBlueAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeechText() {
    final hasRaw = rawSpeechText.isNotEmpty;
    final hasKeywords =
        compressedKeywords.isNotEmpty &&
        compressedKeywords.toLowerCase() != rawSpeechText.toLowerCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Heard',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            hasRaw ? rawSpeechText : 'Waiting for speech...',
            style: TextStyle(
              color: hasRaw ? Colors.white : Colors.white38,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasKeywords) ...[
            const SizedBox(height: 8),
            const Text(
              'Keywords',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              compressedKeywords,
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageRow() {
    if (segments.isEmpty) {
      return Container(
        width: double.infinity,
        height: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Sign images will appear here',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: segments.map((seg) {
            if (seg.isWordSpace) {
              return const SizedBox(width: 20);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white10,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        seg.imageBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    seg.char!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
