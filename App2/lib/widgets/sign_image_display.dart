import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/sign_image_service.dart';

enum SpeechListenStatus { idle, listening, processing }

/// Bottom panel displayed when the app is in speech mode (no hand detected).
/// Shows the raw speech transcription, extracted keywords, and a horizontal
/// scrollable row of sign tiles — either letter PNG images or looping word videos.
class SignImageDisplay extends StatelessWidget {
  final List<SignImageSegment> segments;
  final SpeechListenStatus listenStatus;
  final bool isProcessing;

  const SignImageDisplay({
    super.key,
    required this.segments,
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
          _buildImageRow(),
        ],
      ),
    );
  }

  Widget _buildModeIndicator() {
    final isListening = listenStatus == SpeechListenStatus.listening;
    final isProcessingState = listenStatus == SpeechListenStatus.processing;

    final Color borderColor =
        isListening ? const Color(0xFF60A5FA) : const Color(0xFF2A3E30);
    final Color bgColor = isListening
        ? const Color(0xFF60A5FA).withValues(alpha: 0.12)
        : const Color(0xFF1A2820);

    String label;
    if (isProcessingState) {
      label = 'Processing...';
    } else if (isListening) {
      label = 'Listening...';
    } else {
      label = 'Microphone ready — speak anytime';
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
            color: isListening
                ? const Color(0xFF60A5FA)
                : const Color(0xFF6B7280),
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isListening
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF6B7280),
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
                color: Color(0xFF8B5CF6),
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
          color: const Color(0xFF1A2820),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Sign images will appear here',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2820),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: segments.map((seg) {
            // ── word-space gap ─────────────────────────────
            if (seg.isWordSpace) {
              return const SizedBox(width: 20);
            }

            // ── word-level GIF tile ────────────────────────
            if (seg.isGif) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _GifTile(
                  assetPath: seg.gifAssetPath!,
                  label: seg.word!,
                ),
              );
            }

            // ── letter / number PNG tile (existing) ────────
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
                      color: const Color(0xFF222E28),
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
                      color: Color(0xFF92A395),
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

// ─────────────────────────────────────────────────────────────
//  GIF tile — displays a looping GIF for a whole sign word
// ─────────────────────────────────────────────────────────────

class _GifTile extends StatelessWidget {
  final String assetPath;
  final String label;

  const _GifTile({required this.assetPath, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // GIF frame — 80×80 to stand out from 64×64 letter tiles
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: AppConfig.obBorder,
            border: Border.all(color: AppConfig.obPrimary, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              assetPath,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppConfig.obBorder,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gif_outlined,
                        color: AppConfig.obPrimary.withValues(alpha: 0.5),
                        size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'No GIF',
                      style: TextStyle(
                        color: AppConfig.obPrimary.withValues(alpha: 0.5),
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Word label in primary color to distinguish from letter labels
        Text(
          label,
          style: const TextStyle(
            color: AppConfig.obPrimary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Small "GIF" badge
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppConfig.obPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'GIF',
            style: TextStyle(
              color: AppConfig.obPrimaryDark,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
