import 'dart:io';
import 'package:intl/intl.dart';

class RecordingItem {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int durationMs;
  final DateTime timestamp;
  final int width;
  final int height;
  final String? thumbnailPath;

  const RecordingItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.durationMs,
    required this.timestamp,
    required this.width,
    required this.height,
    this.thumbnailPath,
  });

  bool get fileExists => File(path).existsSync();

  String get formattedDuration {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final hours = minutes ~/ 60;

    if (hours > 0) {
      final remMinutes = minutes % 60;
      return '${hours.toString().padLeft(2, '0')}:${remMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp);
  }

  String get resolutionLabel {
    if (width > 0 && height > 0) {
      if (width >= 1920 || height >= 1920) return '1080p FHD';
      if (width >= 1280 || height >= 1280) return '720p HD';
      if (width >= 640 || height >= 640) return '480p SD';
      return '${width}x$height';
    }
    return 'MP4 Video';
  }

  factory RecordingItem.fromMap(Map<dynamic, dynamic> map) {
    return RecordingItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Recording',
      path: map['path']?.toString() ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      thumbnailPath: map['thumbnailPath']?.toString(),
    );
  }
}
