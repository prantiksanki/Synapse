import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

/// Downloads and stores the T5 grammar ONNX model files on first launch.
/// Files live in the app support directory and persist across launches.
class T5ModelDownloader {
  Future<Directory> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/t5_model');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _file(String name) async => File('${(await _modelDir()).path}/$name');

  Future<String> encoderPath() async => (await _file(AppConfig.t5EncoderFileName)).path;
  Future<String> decoderPath() async => (await _file(AppConfig.t5DecoderFileName)).path;
  Future<String> vocabPath() async => (await _file(AppConfig.t5VocabFileName)).path;

  Future<Map<String, int>> readConfig() async {
    return {'hidden_dim': 512, 'vocab_size': 32100, 'max_len': 64};
  }

  Future<bool> _fileReady(String name) async {
    final f = await _file(name);
    if (!await f.exists()) return false;
    return await f.length() > 1024;
  }

  Future<bool> allModelsDownloaded() async =>
      await _fileReady(AppConfig.t5EncoderFileName) &&
      await _fileReady(AppConfig.t5DecoderFileName) &&
      await _fileReady(AppConfig.t5VocabFileName);

  Future<void> downloadAll({
    required void Function(String fileLabel, int received, int total) onProgress,
  }) async {
    await _downloadFile(
      url: AppConfig.t5VocabUrl,
      name: AppConfig.t5VocabFileName,
      label: 'Tokenizer (~2 MB)',
      onProgress: onProgress,
    );
    await _downloadFile(
      url: AppConfig.t5EncoderUrl,
      name: AppConfig.t5EncoderFileName,
      label: 'Encoder (~36 MB)',
      onProgress: onProgress,
    );
    await _downloadFile(
      url: AppConfig.t5DecoderUrl,
      name: AppConfig.t5DecoderFileName,
      label: 'Decoder (~59 MB)',
      onProgress: onProgress,
    );
  }

  Future<void> _downloadFile({
    required String url,
    required String name,
    required String label,
    required void Function(String, int, int) onProgress,
  }) async {
    final target = await _file(name);
    final temp = File('${target.path}.part');
    final client = HttpClient();

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed for $label (HTTP ${response.statusCode})',
          uri: Uri.parse(url),
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = temp.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(label, received, total);
      }

      await sink.flush();
      await sink.close();

      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> deleteAll() async {
    for (final name in [
      AppConfig.t5VocabFileName,
      AppConfig.t5EncoderFileName,
      AppConfig.t5DecoderFileName,
    ]) {
      final f = await _file(name);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }
}
