import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/detection_provider.dart';
import 'detection_screen.dart';

/// Shown on first launch when T5 model files are not yet on device.
/// Displays a download progress UI and navigates to [DetectionScreen] when done.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  bool _started = false;
  bool _failed = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
  }

  Future<void> _startDownload() async {
    if (_started) return;
    _started = true;
    _failed = false;

    final provider = context.read<DetectionProvider>();

    try {
      await provider.downloadAndLoadGrammarModel();
      if (!mounted) return;

      if (provider.grammarStatus == GrammarModelStatus.ready ||
          provider.grammarStatus == GrammarModelStatus.error) {
        // Navigate to detection screen regardless — error just means Dart fallback
        _goToDetection();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _goToDetection() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DetectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Consumer<DetectionProvider>(
            builder: (context, provider, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App logo / name
                  const Text(
                    AppConfig.appTitle,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign Language to Speech',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 64),

                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      color: Colors.lightBlueAccent,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    'Downloading Grammar Model',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is a one-time download of ${AppConfig.t5ModelSizeLabel}.\n'
                    'The model runs fully offline after this.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 40),

                  // Progress
                  if (!_failed) _buildProgress(provider),
                  if (_failed) _buildError(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(DetectionProvider provider) {
    final status = provider.grammarStatus;
    final message = provider.grammarStatusMessage ?? '';
    final progress = provider.downloadProgress;
    final fileLabel = provider.downloadFileLabel;

    // Done — navigate immediately
    if (status == GrammarModelStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToDetection());
    }

    final isLoading = status == GrammarModelStatus.loading;
    final isDone = status == GrammarModelStatus.ready;

    return Column(
      children: [
        // File label
        if (fileLabel.isNotEmpty && status == GrammarModelStatus.downloading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'File: $fileLabel',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: isLoading || isDone
                ? (isDone ? 1.0 : null)
                : (progress > 0 ? progress : null),
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDone ? Colors.greenAccent : Colors.lightBlueAccent,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Status message
        Text(
          message.isNotEmpty ? message : 'Preparing…',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),

        if (status == GrammarModelStatus.downloading && progress > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],

        if (isDone) ...[
          const SizedBox(height: 20),
          const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 40),
          const SizedBox(height: 8),
          const Text(
            'Ready! Starting app…',
            style: TextStyle(color: Colors.greenAccent, fontSize: 14),
          ),
        ],
      ],
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Download Failed',
          style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _started = false;
              _failed = false;
              _errorMessage = '';
            });
            _startDownload();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.lightBlueAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _goToDetection,
          child: const Text(
            'Skip — use basic mode',
            style: TextStyle(color: Colors.white38),
          ),
        ),
      ],
    );
  }
}
