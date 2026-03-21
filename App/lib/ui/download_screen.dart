// download_screen.dart — First-run screen that downloads the TinyLlama model.
//
// Shown when no model file is found on disk. The user can either:
//   a) Download TinyLlama-1.1B-Chat Q4_K_M (~670 MB) from HuggingFace, or
//   b) Skip and proceed to CameraScreen without LLM sentence generation.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../model_downloader.dart';
import 'camera_screen.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------
  _ScreenState _state = _ScreenState.idle;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorText;

  /// Dio cancel token so the user can abort a running download.
  CancelToken? _cancelToken;

  final _downloader = ModelDownloader();

  // Download speed tracking
  double _speedMBps = 0.0;
  DateTime _lastSpeedSample = DateTime.now();
  int _lastReceivedBytes = 0;

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _startDownload() async {
    setState(() {
      _state      = _ScreenState.downloading;
      _progress   = 0.0;
      _statusText = 'Connecting…';
      _errorText  = null;
    });

    _cancelToken = CancelToken();

    try {
      await _downloader.downloadModel(
        (progress) {
          if (!mounted) return;
          final now = DateTime.now();
          final elapsed = now.difference(_lastSpeedSample).inMilliseconds;

          // Update speed estimate once per second
          if (elapsed >= 1000) {
            final totalSize = 670 * 1024 * 1024; // ~670 MB
            final receivedBytes = (progress * totalSize).toInt();
            final deltaBytes = receivedBytes - _lastReceivedBytes;
            _speedMBps = (deltaBytes / elapsed * 1000) / (1024 * 1024);
            _lastReceivedBytes = receivedBytes;
            _lastSpeedSample = now;
          }

          final pct = (progress * 100).toStringAsFixed(1);
          final speedStr = _speedMBps > 0
              ? '${_speedMBps.toStringAsFixed(1)} MB/s'
              : '';
          final etaStr = _etaString(progress);

          setState(() {
            _progress   = progress;
            _statusText = '$pct% complete  $speedStr  $etaStr';
          });
        },
        cancelToken: _cancelToken,
      );

      if (!mounted) return;

      // Mark model as loaded in global state
      context.read<AppState>().setModelLoaded(true);

      setState(() {
        _state      = _ScreenState.done;
        _statusText = 'Download complete!';
        _progress   = 1.0;
      });

      // Brief pause so the user sees "complete", then navigate
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) _navigateToCamera();
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) {
        setState(() {
          _state      = _ScreenState.idle;
          _statusText = '';
          _errorText  = null;
        });
      } else {
        setState(() {
          _state     = _ScreenState.error;
          _errorText = 'Download failed: ${e.message}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state     = _ScreenState.error;
        _errorText = 'Unexpected error: $e';
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('User cancelled');
  }

  void _navigateToCamera() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  String _etaString(double progress) {
    if (progress <= 0 || _speedMBps <= 0) return '';
    final totalMB    = 670.0;
    final doneMB     = progress * totalMB;
    final remainMB   = totalMB - doneMB;
    final etaSec     = remainMB / _speedMBps;
    if (etaSec < 60)  return 'ETA ${etaSec.toStringAsFixed(0)}s';
    if (etaSec < 3600) {
      final m = (etaSec / 60).floor();
      final s = (etaSec % 60).toStringAsFixed(0);
      return 'ETA ${m}m ${s}s';
    }
    return '';
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // ── Logo / title ─────────────────────────────────────────────
              _buildHeader(),

              const Spacer(flex: 1),

              // ── Info card ────────────────────────────────────────────────
              _buildInfoCard(),

              const SizedBox(height: 32),

              // ── Progress area ─────────────────────────────────────────────
              if (_state == _ScreenState.downloading) ...[
                _buildProgressArea(),
                const SizedBox(height: 20),
              ],

              // ── Error message ─────────────────────────────────────────────
              if (_errorText != null) ...[
                _buildErrorBanner(),
                const SizedBox(height: 16),
              ],

              // ── Primary action button ────────────────────────────────────
              _buildPrimaryButton(),

              const SizedBox(height: 12),

              // ── Skip button ───────────────────────────────────────────────
              if (_state != _ScreenState.downloading)
                TextButton(
                  onPressed: _navigateToCamera,
                  child: const Text(
                    'Skip — use without AI sentences',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Sub-widgets --------------------------------------------------------

  Widget _buildHeader() => Column(
        children: [
          // Glowing purple circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6C63FF).withOpacity(0.15),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.sign_language,
              color: Color(0xFF6C63FF),
              size: 38,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'SYNAPSE',
            style: TextStyle(
              color: Color(0xFF6C63FF),
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign Language → Natural Language',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      );

  Widget _buildInfoCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Model Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.download,
              label: 'TinyLlama-1.1B-Chat (Q4_K_M)',
            ),
            _InfoRow(
              icon: Icons.storage,
              label: 'Size: ${_downloader.getModelSizeGB()}',
            ),
            _InfoRow(
              icon: Icons.wifi,
              label: 'Requires Wi-Fi recommended',
            ),
            _InfoRow(
              icon: Icons.lock_outline,
              label: 'Runs 100% on-device — no data sent',
            ),
          ],
        ),
      );

  Widget _buildProgressArea() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6C63FF),
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      );

  Widget _buildErrorBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFCF6679).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCF6679).withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFCF6679), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorText!,
                style: const TextStyle(
                    color: Color(0xFFCF6679), fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Widget _buildPrimaryButton() {
    switch (_state) {
      case _ScreenState.idle:
      case _ScreenState.error:
        return ElevatedButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.download),
          label: Text(_state == _ScreenState.error
              ? 'Retry Download'
              : 'Download TinyLlama (~${_downloader.getModelSizeGB()})'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
          ),
        );

      case _ScreenState.downloading:
        return OutlinedButton.icon(
          onPressed: _cancelDownload,
          icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
          label: const Text('Cancel Download',
              style: TextStyle(color: Colors.white54)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );

      case _ScreenState.done:
        return ElevatedButton.icon(
          onPressed: _navigateToCamera,
          icon: const Icon(Icons.check),
          label: const Text('Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

enum _ScreenState { idle, downloading, done, error }

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6C63FF), size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}
