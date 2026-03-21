// result_widget.dart — Displays the LLM-generated sentence with copy and TTS actions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays a generated sentence in a styled card.
///
/// Features:
///   - Animated fade-in when a new sentence arrives
///   - Copy-to-clipboard button
///   - TTS speak button (callback to parent)
///   - Confidence-coloured progress bar (green / amber / red)
class ResultWidget extends StatefulWidget {
  final String sentence;
  final VoidCallback? onSpeak;

  const ResultWidget({
    super.key,
    required this.sentence,
    this.onSpeak,
  });

  @override
  State<ResultWidget> createState() => _ResultWidgetState();
}

class _ResultWidgetState extends State<ResultWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(ResultWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-animate whenever the sentence changes
    if (oldWidget.sentence != widget.sentence) {
      _animController.reset();
      _animController.forward();
      setState(() => _copied = false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.sentence));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sentence copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF6C63FF),
      ),
    );
    // Reset the copied icon after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.08),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ───────────────────────────────────────────────
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF6C63FF),
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Generated Sentence',
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                // Copy button
                _ActionIconButton(
                  icon: _copied ? Icons.check : Icons.copy,
                  tooltip: _copied ? 'Copied!' : 'Copy',
                  color: _copied ? Colors.green : Colors.white54,
                  onTap: _copyToClipboard,
                ),
                const SizedBox(width: 4),
                // Speak button
                if (widget.onSpeak != null)
                  _ActionIconButton(
                    icon: Icons.volume_up,
                    tooltip: 'Speak',
                    color: Colors.white54,
                    onTap: widget.onSpeak!,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Sentence text ─────────────────────────────────────────────
            Text(
              widget.sentence,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small icon button used inside ResultWidget
// ---------------------------------------------------------------------------

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );
}
