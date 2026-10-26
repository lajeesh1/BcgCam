import 'package:flutter_test/flutter_test.dart';
import 'package:bcgcam/models/recording_item.dart';
import 'package:bcgcam/models/camera_info.dart';

void main() {
  group('Models Unit Tests', () {
    test('CameraInfo parsing and getters', () {
      final cam = CameraInfo.fromMap({
        'id': '0',
        'lensFacing': 'back',
        'name': 'Rear Camera',
        'supportedResolutions': ['1080p', '720p', '480p'],
      });

      expect(cam.id, '0');
      expect(cam.isBack, isTrue);
      expect(cam.isFront, isFalse);
      expect(cam.name, 'Rear Camera');
      expect(cam.supportedResolutions, contains('1080p'));
    });

    test('RecordingItem formatters and calculations', () {
      final item = RecordingItem(
        id: 'VID_1.mp4',
        name: 'VID_1.mp4',
        path: '/storage/emulated/0/Movies/BackgroundVideoRecorder/VID_1.mp4',
        sizeBytes: 52428800, // 50 MB
        durationMs: 125000, // 2 min 5 sec
        timestamp: DateTime(2026, 10, 26, 12, 30),
        width: 1920,
        height: 1080,
      );

      expect(item.formattedDuration, '02:05');
      expect(item.formattedSize, '50.0 MB');
      expect(item.resolutionLabel, '1080p FHD');
    });
  });
}
