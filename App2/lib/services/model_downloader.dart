import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

class ModelDownloader {
  Future<Directory> getModelDirectory() async {
    final baseDir = await getExternalStorageDirectory();
    if (baseDir == null) {
      throw const FileSystemException('External storage is unavailable.');
    }

    final modelDir = Directory('${baseDir.path}/${AppConfig.modelDirectoryName}');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  Future<File> getModelFile() async {
    final modelDir = await getModelDirectory();
    return File('${modelDir.path}/${AppConfig.llamaModelFileName}');
  }

  Future<bool> modelExists() async {
    final file = await getModelFile();
    return file.exists();
  }

  Future<String> resolveModelPath() async {
    final file = await getModelFile();
    return file.path;
  }

  Future<File> downloadModel({
    required void Function(int received, int total) onProgress,
  }) async {
    final targetFile = await getModelFile();
    final tempFile = File('${targetFile.path}.part');
    final client = HttpClient();

    try {
      final request = await client.getUrl(Uri.parse(AppConfig.llamaModelUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Model download failed with status ${response.statusCode}.',
          uri: Uri.parse(AppConfig.llamaModelUrl),
        );
      }

      final sink = tempFile.openWrite();
      final total = response.contentLength;
      var received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }

      await sink.flush();
      await sink.close();

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      return targetFile;
    } finally {
      client.close(force: true);
    }
  }
}
