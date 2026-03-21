import 'package:flutter/material.dart';
import '../models/gesture_result.dart';
import '../models/llm_generation_result.dart';
import '../models/model_download_state.dart';
import '../models/word_buffer_state.dart';

class GestureDisplay extends StatelessWidget {
  final GestureResult? result;
  final double fps;
  final WordBufferState wordBufferState;
  final LlmGenerationResult generationResult;
  final ModelDownloadState modelDownloadState;
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
    required this.modelDownloadState,
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
          // FPS counter
          _buildFpsCounter(),
          const SizedBox(height: 8),
          _buildModelStatus(),
          const SizedBox(height: 8),
          _buildWordBuffer(),
          const SizedBox(height: 8),
          _buildSentencePanel(),
          const SizedBox(height: 8),
          // Gesture result
          _buildGestureResult(),
        ],
      ),
    );
  }

  Widget _buildFpsCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'FPS: ${fps.toStringAsFixed(1)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildModelStatus() {
    final text = switch (modelDownloadState.status) {
      ModelDownloadStatus.idle => 'Model idle',
      ModelDownloadStatus.checking => 'Checking local TinyLlama model...',
      ModelDownloadStatus.missing => 'Model missing. Starting download...',
      ModelDownloadStatus.downloading =>
        'Downloading model ${(modelDownloadState.progress * 100).toStringAsFixed(0)}%',
      ModelDownloadStatus.ready => 'Model downloaded. Preparing to load...',
      ModelDownloadStatus.loading => 'Loading TinyLlama...',
      ModelDownloadStatus.loaded =>
        'TinyLlama ready for offline sentence generation',
      ModelDownloadStatus.error => modelDownloadState.error ?? 'Model error',
    };

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
            'Model Status',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: Colors.white70)),
          if (modelDownloadState.status == ModelDownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: modelDownloadState.progress > 0
                  ? modelDownloadState.progress
                  : null,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.lightBlueAccent,
              ),
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
        color: Colors.black54,
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
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Manual send button — commits buffer immediately
              if (onSend != null)
                TextButton.icon(
                  onPressed: onSend,
                  icon: const Icon(
                    Icons.send,
                    size: 16,
                    color: Colors.lightBlueAccent,
                  ),
                  label: const Text(
                    'Send',
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
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
              color: hasTokens ? Colors.white : Colors.white70,
              fontSize: 16,
              fontWeight: hasTokens ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (wordBufferState.lastCommittedPhrase.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Last: ${wordBufferState.lastCommittedPhrase}',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
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
              ? 'Generating sentence...'
              : 'No sentence generated yet.');
    final pendingTokens = wordBufferState.activePhrase.trim();
    final sentTokens = generationResult.inputTokens.trim();
    final source = generationResult.source.trim();

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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Natural Sentence',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (generationResult.hasSentence && onSpeak != null)
                IconButton(
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up, color: Colors.white),
                ),
            ],
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: source == 'TinyLlama'
                    ? Colors.green.withValues(alpha: 0.18)
                    : Colors.orange.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: source == 'TinyLlama' ? Colors.green : Colors.orange,
                ),
              ),
              child: Text(
                'Source: $source',
                style: TextStyle(
                  color: source == 'TinyLlama' ? Colors.green : Colors.orange,
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
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              sentence,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          if (pendingTokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Pending tokens: $pendingTokens',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontSize: 13,
              ),
            ),
          ],
          if (generationResult.error != null &&
              generationResult.error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              generationResult.error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          if (sentTokens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tokens sent to LLM: $sentTokens',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
          if (generationResult.hasSentence) ...[
            const SizedBox(height: 4),
            Text(
              'Latency: ${generationResult.latencyMs} ms',
              style: const TextStyle(color: Colors.white54),
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
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          hasHandDetected
              ? 'Hand detected, classifying...'
              : 'No hand detected',
          style: const TextStyle(color: Colors.white70, fontSize: 18),
        ),
      );
    }

    final isConfident = result!.confidence >= confidenceThreshold;
    final labelColor = isConfident ? Colors.white : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isConfident
            ? _getGestureColor(result!.label).withValues(alpha: 0.8)
            : Colors.black54,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfident ? Colors.white : Colors.grey,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gesture icon
          Icon(_getGestureIcon(result!.label), color: labelColor, size: 48),
          const SizedBox(height: 8),
          // Gesture label
          Text(
            result!.label,
            style: TextStyle(
              color: labelColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Confidence
          Text(
            result!.confidencePercent,
            style: TextStyle(
              color: labelColor.withValues(alpha: 0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // Probability bars
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
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              Expanded(
                child: LinearProgressIndicator(
                  value: entry.value,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSelected ? Colors.white : Colors.white54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${(entry.value * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
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
        return Colors.green;
      case 'Close':
        return Colors.red;
      case 'Pointer':
        return Colors.blue;
      case 'OK':
        return Colors.orange;
      default:
        return Colors.grey;
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
