enum ModelDownloadStatus {
  idle,
  checking,
  missing,
  downloading,
  ready,
  loading,
  loaded,
  error,
}

class ModelDownloadState {
  final ModelDownloadStatus status;
  final double progress;
  final int bytesDownloaded;
  final int totalBytes;
  final String? localPath;
  final String? error;

  const ModelDownloadState({
    required this.status,
    this.progress = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.localPath,
    this.error,
  });

  const ModelDownloadState.idle() : this(status: ModelDownloadStatus.idle);

  bool get isBusy =>
      status == ModelDownloadStatus.checking ||
      status == ModelDownloadStatus.downloading ||
      status == ModelDownloadStatus.loading;

  bool get isLoaded => status == ModelDownloadStatus.loaded;
}
