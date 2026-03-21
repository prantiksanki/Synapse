// model_downloader.dart — Downloads and manages the TinyLlama GGUF model file.
//
// The model (~670 MB) is downloaded once from HuggingFace and stored on the
// device's external storage so it persists across app updates.
//
// Usage:
//   final dl = ModelDownloader();
//   if (!await dl.modelExists()) {
//     await dl.downloadModel((progress) => setState(() => _progress = progress));
//   }
//   final path = await dl.getModelPath();

import 'dart:io';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Manages download and storage of the TinyLlama-1.1B-Chat Q4_K_M GGUF model.
class ModelDownloader {
  // -------------------------------------------------------------------------
  // Model metadata
  // -------------------------------------------------------------------------

  static const String _modelUrl =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF'
      '/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  static const String _modelFilename =
      'tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  /// Human-readable model size for display in the download screen.
  String getModelSizeGB() => '0.67 GB';

  // -------------------------------------------------------------------------
  // Path helpers
  // -------------------------------------------------------------------------

  /// Returns the absolute path where the model file should be stored.
  ///
  /// Uses external storage so the large file doesn't consume internal app
  /// storage quota. Falls back to the app documents directory if external
  /// storage is unavailable.
  Future<String> getModelPath() async {
    Directory? dir;
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();

    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return '${modelsDir.path}/$_modelFilename';
  }

  /// Returns true if the model file exists at the expected path.
  Future<bool> modelExists() async {
    try {
      final path = await getModelPath();
      final file = File(path);
      final exists = await file.exists();
      if (exists) {
        final size = await file.length();
        // Sanity-check: a valid GGUF file should be at least 100 MB
        if (size < 100 * 1024 * 1024) {
          dev.log(
            'Model file exists but is suspiciously small ($size bytes) — treating as missing.',
            name: 'ModelDownloader',
          );
          return false;
        }
      }
      return exists;
    } catch (e) {
      dev.log('modelExists check failed: $e', name: 'ModelDownloader');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Download
  // -------------------------------------------------------------------------

  /// Download the model file with progress reporting.
  ///
  /// [onProgress] is called with values from 0.0 to 1.0 as the download
  /// progresses. Throws on network error or cancellation.
  Future<void> downloadModel(
    void Function(double progress) onProgress, {
    CancelToken? cancelToken,
  }) async {
    final savePath = await getModelPath();
    dev.log('Downloading model to: $savePath', name: 'ModelDownloader');

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(seconds: 30),
    ));

    try {
      await dio.download(
        _modelUrl,
        savePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress.clamp(0.0, 1.0));
            dev.log(
              'Download progress: ${(progress * 100).toStringAsFixed(1)}% '
              '($received / $total bytes)',
              name: 'ModelDownloader',
            );
          }
        },
        options: Options(
          headers: {
            // HuggingFace does not require auth for public GGUF files
            'User-Agent': 'SYNAPSE-App/1.0',
          },
          responseType: ResponseType.stream,
        ),
      );

      dev.log('Model download complete: $savePath', name: 'ModelDownloader');
      onProgress(1.0);
    } on DioException catch (e) {
      dev.log('Download failed: ${e.message}', name: 'ModelDownloader', level: 900);
      // Clean up partial download
      final partial = File(savePath);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// Delete the model file from disk (e.g. to re-download after corruption).
  Future<void> deleteModel() async {
    try {
      final path = await getModelPath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        dev.log('Model file deleted: $path', name: 'ModelDownloader');
      }
    } catch (e) {
      dev.log('deleteModel error: $e', name: 'ModelDownloader');
    }
  }
}
