import 'dart:io';
import 'package:share_plus/share_plus.dart';

class StorageService {
  static Future<void> shareVideo(String filePath, {String? title}) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Video file not found at $filePath');
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: 'video/mp4')],
        text: title ?? 'Recorded with Background Video Recorder',
      ),
    );
  }
}

