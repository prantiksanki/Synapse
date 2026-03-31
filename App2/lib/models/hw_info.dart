class HwInfo {
  final String device;
  final String version;
  final String ip;
  final String camera;
  final bool cameraOk;
  final bool micOk;
  final bool speakerOk;

  const HwInfo({
    required this.device,
    required this.version,
    required this.ip,
    required this.camera,
    required this.cameraOk,
    required this.micOk,
    required this.speakerOk,
  });

  factory HwInfo.fromJson(Map<String, dynamic> json) {
    return HwInfo(
      device: json['device'] as String? ?? 'VAANI-HW',
      version: json['version'] as String? ?? '?',
      ip: json['ip'] as String? ?? '',
      camera: json['camera'] as String? ?? '',
      cameraOk: json['camera_ok'] as bool? ?? false,
      micOk: json['mic_ok'] as bool? ?? false,
      speakerOk: json['speaker_ok'] as bool? ?? false,
    );
  }
}
