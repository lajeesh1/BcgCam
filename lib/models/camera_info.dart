class CameraInfo {
  final String id;
  final String lensFacing;
  final String name;
  final List<String> supportedResolutions;

  const CameraInfo({
    required this.id,
    required this.lensFacing,
    required this.name,
    required this.supportedResolutions,
  });

  bool get isFront => lensFacing.toLowerCase() == 'front';
  bool get isBack => lensFacing.toLowerCase() == 'back';

  factory CameraInfo.fromMap(Map<dynamic, dynamic> map) {
    return CameraInfo(
      id: map['id']?.toString() ?? '0',
      lensFacing: map['lensFacing']?.toString() ?? 'back',
      name: map['name']?.toString() ?? 'Camera',
      supportedResolutions: (map['supportedResolutions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['720p'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lensFacing': lensFacing,
      'name': name,
      'supportedResolutions': supportedResolutions,
    };
  }
}
