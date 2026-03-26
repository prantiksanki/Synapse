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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFpsCounter(),
          const SizedBox(height: 8),
          _buildModelStatus(),
          const SizedBox(height: 8),
          _buildWordBuffer(),
          const SizedBox(height: 8),
          _buildSentencePanel(),
          const SizedBox(height: 8),
          _buildGestureResult(),
        ],
      ),
    );
  }

  Widget _buildFpsCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'FPS: ${fps.toStringAsFixed(1)}',
        style: const TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildModelStatus() {
    final String text;
    final Color indicatorColor;

    switch (grammarStatus) {
      case GrammarModelStatus.idle:
        text = 'Grammar model idle';
        indicatorColor = const Color(0xFF9CA3AF);
      case GrammarModelStatus.downloading:
        text = 'Downloading grammar model…';
        indicatorColor = const Color(0xFF8B5CF6);
      case GrammarModelStatus.loading:
        text = 'Loading grammar model…';
        indicatorColor = const Color(0xFF8B5CF6);
      case GrammarModelStatus.ready:
        text = 'T5 grammar model ready (offline)';
        indicatorColor = const Color(0xFF34D399);
      case GrammarModelStatus.error:
        text = grammarLoadError != null
            ? 'Grammar model error: $grammarLoadError\n(Using Dart fallback)'
            : 'Grammar model failed to load — using Dart fallback.';
        indicatorColor = const Color(0xFFF59E0B);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Model Status',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: Color(0xFF4B5563))),
          if (grammarStatus == GrammarModelStatus.loading) ...[
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
        color: const Color(0xFFF8F7FF),
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
                    color: Color(0xFF1A1A2E),
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
              color: hasTokens ? const Color(0xFF1A1A2E) : const Color(0xFF4B5563),
              fontSize: 16,
              fontWeight: hasTokens ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (wordBufferState.lastCommittedPhrase.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Last: ${wordBufferState.lastCommittedPhrase}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSentencePanel() {
    final sentence = generationResult.hasSentence
        ? generationResult.sentence
        : (isGeneratingSentence
              ? 'Correcting grammar...'
              : 'No sentence generated yet.');
    final sentTokens = generationResult.inputTokens.trim();
    final source = generationResult.source.trim();

    final bool isT5 = source == 'T5-Grammar';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Natural Sentence',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.bold,
            ),
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isT5
                    ? const Color(0xFF34D399).withValues(alpha: 0.15)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isT5 ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                ),
              ),
              child: Text(
                'Source: $source',
                style: TextStyle(
                  color: isT5 ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EEFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              sentence,
              style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          if (generationResult.error != null &&
              generationResult.error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              generationResult.error!,
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          ],
          if (sentTokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tokens sent to model: $sentTokens',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ],
          if (generationResult.hasSentence) ...[
            const SizedBox(height: 4),
            Text(
              'Latency: ${generationResult.latencyMs} ms',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGestureResult() {
    if (result == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          hasHandDetected
              ? 'Hand detected, classifying...'
              : 'No hand detected',
          style: const TextStyle(color: Color(0xFF4B5563), fontSize: 18),
        ),
      );
    }

    final isConfident = result!.confidence >= confidenceThreshold;
    final labelColor = isConfident ? Colors.white : const Color(0xFF4B5563);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isConfident
            ? _getGestureColor(result!.label).withValues(alpha: 0.8)
            : const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfident
              ? Colors.white.withValues(alpha: 0.8)
              : const Color(0xFFE5E7EB),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getGestureIcon(result!.label), color: labelColor, size: 48),
          const SizedBox(height: 8),
          Text(
            result!.label,
            style: TextStyle(
              color: labelColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result!.confidencePercent,
            style: TextStyle(
              color: labelColor.withValues(alpha: 0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          _buildProbabilityBars(),
        ],
      ),
    );
  }

  Widget _buildProbabilityBars() {
    if (result == null) return const SizedBox.shrink();

    return Column(
      children: result!.probabilities.entries.map((entry) {
        final isSelected = entry.key == result!.label;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF4B5563),
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              Expanded(
                child: LinearProgressIndicator(
                  value: entry.value,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSelected ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${(entry.value * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF4B5563),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getGestureColor(String label) {
    switch (label) {
      case 'Open':
        return const Color(0xFF34D399);
      case 'Close':
        return const Color(0xFFEF4444);
      case 'Pointer':
        return const Color(0xFF60A5FA);
      case 'OK':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  IconData _getGestureIcon(String label) {
    switch (label) {
      case 'Open':
        return Icons.pan_tool;
      case 'Close':
        return Icons.front_hand;
      case 'Pointer':
        return Icons.touch_app;
      case 'OK':
        return Icons.thumb_up;
      default:
        return Icons.help_outline;
    }
  }
}
