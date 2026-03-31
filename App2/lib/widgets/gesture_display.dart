import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/gesture_result.dart';
import '../models/llm_generation_result.dart';
import '../models/word_buffer_state.dart';
import '../providers/detection_provider.dart';

class GestureDisplay extends StatelessWidget {
  final GestureResult? result;
  final double fps;
  final WordBufferState wordBufferState;
  final LlmGenerationResult generationResult;
  final GrammarModelStatus grammarStatus;
  final String? grammarLoadError;
  final bool hasHandDetected;
  final bool isGeneratingSentence;
  final VoidCallback? onSpeak;
  final VoidCallback? onSend;
  final double confidenceThreshold;
  final Uint8List? signImageBytes;

  const GestureDisplay({
    super.key,
    required this.result,
    required this.fps,
    required this.wordBufferState,
    required this.generationResult,
    required this.grammarStatus,
    this.grammarLoadError,
    required this.hasHandDetected,
    required this.isGeneratingSentence,
    this.onSpeak,
    this.onSend,
    this.confidenceThreshold = 0.5,
    this.signImageBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showModelStatus) _buildModelStatus(),
          if (_showModelStatus) const SizedBox(height: 8),
          _buildWordBuffer(),
          const SizedBox(height: 8),
          _buildSentencePanel(),
          const SizedBox(height: 8),
          _buildGestureResult(),
        ],
      ),
    );
  }

  // Only show model status while it's actively loading or has errored.
  bool get _showModelStatus =>
      grammarStatus == GrammarModelStatus.downloading ||
      grammarStatus == GrammarModelStatus.loading ||
      grammarStatus == GrammarModelStatus.error;

  Widget _buildModelStatus() {
    final String text;
    final Color indicatorColor;

    switch (grammarStatus) {
      case GrammarModelStatus.downloading:
        text = 'Downloading grammar model…';
        indicatorColor = const Color(0xFF8B5CF6);
      case GrammarModelStatus.loading:
        text = 'Loading grammar model…';
        indicatorColor = const Color(0xFF8B5CF6);
      case GrammarModelStatus.error:
        text = 'Grammar model failed — using fallback.';
        indicatorColor = const Color(0xFFF59E0B);
      default:
        text = '';
        indicatorColor = const Color(0xFF9CA3AF);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2820),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: const TextStyle(color: Color(0xFF92A395))),
              ),
            ],
          ),
          if (grammarStatus == GrammarModelStatus.loading ||
              grammarStatus == GrammarModelStatus.downloading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              backgroundColor: Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWordBuffer() {
    final hasTokens = wordBufferState.activeTokens.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2820),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Detected Sign Buffer',
                  style: TextStyle(
                    color: Color(0xFFF1F7E8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onSend != null)
                TextButton.icon(
                  onPressed: onSend,
                  icon: const Icon(
                    Icons.send,
                    size: 16,
                    color: Color(0xFF8B5CF6),
                  ),
                  label: const Text(
                    'Send',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 13,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasTokens
                ? wordBufferState.activePhrase
                : 'Waiting for stable sign tokens...',
            style: TextStyle(
              color: hasTokens ? const Color(0xFFF1F7E8) : const Color(0xFF92A395),
              fontSize: 16,
              fontWeight: hasTokens ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentencePanel() {
    final sentence = generationResult.hasSentence
        ? generationResult.sentence
        : (isGeneratingSentence ? 'Correcting grammar...' : 'No sentence yet.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2820),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Natural Sentence',
            style: TextStyle(
              color: Color(0xFFF1F7E8),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF222E28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A3E30)),
            ),
            child: Text(
              sentence,
              style: const TextStyle(
                color: Color(0xFFF1F7E8),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestureResult() {
    if (result == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2820),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          hasHandDetected ? 'Classifying...' : 'No hand detected',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF92A395), fontSize: 16),
        ),
      );
    }

    final label = result!.label;
    final imageBytes = signImageBytes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hand sign image — large, like the reference picture
          imageBytes != null
              ? Image.memory(
                  imageBytes,
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                )
              : SizedBox(
                  width: 140,
                  height: 140,
                  child: Center(
                    child: Icon(
                      Icons.sign_language_rounded,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
          const SizedBox(height: 10),
          // Letter label — large bold, same style as reference
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result!.confidencePercent,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
