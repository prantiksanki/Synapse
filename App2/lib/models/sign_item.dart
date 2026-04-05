class SignItem {
  final String id;
  final String label;
  final String? imagePath;
  final String? videoPath;

  const SignItem({
    required this.id,
    required this.label,
    this.imagePath,
    this.videoPath,
  });

  bool get hasVideo => videoPath != null;
  bool get hasImage => imagePath != null;
}