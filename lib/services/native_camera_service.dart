import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/camera_info.dart';
import '../models/recording_item.dart';

class RecordingFinishedEvent {
  final String filePath;
  final String fileName;
  final int durationSeconds;
  final int sizeBytes;
  final String reason;

  RecordingFinishedEvent({
    required this.filePath,
    required this.fileName,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.reason,
  });
}

class NativeCameraService extends ChangeNotifier {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.bcgcam/recorder');
  static const EventChannel _eventChannel =
      EventChannel('com.example.bcgcam/recorder_events');

  StreamSubscription? _eventSubscription;

  bool _isRecording = false;
  String _status = 'IDLE'; // IDLE, STARTING, RECORDING, STOPPING
  int _elapsedSeconds = 0;
  int _remainingSeconds = 60;
  int _totalDurationSeconds = 60;
  String _activeCameraId = '0';
  String _activeCameraName = 'Rear Camera';
  String _activeQuality = '1080p';
  bool _audioEnabled = true;
  String? _currentFilePath;

  List<CameraInfo> _availableCameras = [];
  Map<String, dynamic> _storageInfo = {};

  final _finishedController = StreamController<RecordingFinishedEvent>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _cancelledController = StreamController<void>.broadcast();

  Stream<RecordingFinishedEvent> get onRecordingFinished => _finishedController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<void> get onRecordingCancelled => _cancelledController.stream;

  bool get isRecording => _isRecording;
  String get status => _status;
  int get elapsedSeconds => _elapsedSeconds;
  int get remainingSeconds => _remainingSeconds;
  int get totalDurationSeconds => _totalDurationSeconds;
  String get activeCameraId => _activeCameraId;
  String get activeCameraName => _activeCameraName;
  String get activeQuality => _activeQuality;
  bool get audioEnabled => _audioEnabled;
  String? get currentFilePath => _currentFilePath;
  List<CameraInfo> get availableCameras => _availableCameras;
  Map<String, dynamic> get storageInfo => _storageInfo;

  int get freeStorageBytes => (_storageInfo['freeBytes'] as num?)?.toInt() ?? 0;
  int get totalStorageBytes => (_storageInfo['totalBytes'] as num?)?.toInt() ?? 0;
  String get storagePath => _storageInfo['path']?.toString() ?? 'Movies/BackgroundVideoRecorder';
  bool get isLowStorage => freeStorageBytes > 0 && freeStorageBytes < 500 * 1024 * 1024; // < 500 MB

  String get formattedFreeStorage {
    if (freeStorageBytes <= 0) return 'Checking...';
    final gb = freeStorageBytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) {
      return '${gb.toStringAsFixed(1)} GB free';
    }
    final mb = freeStorageBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB free';
  }

  Future<void> init() async {
    _startListeningToEvents();
    await refreshCameras();
    await refreshStorageInfo();
    await refreshStatus();
  }

  void _startListeningToEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final eventType = event['event']?.toString();
          if (eventType == 'status') {
            final data = event['data'] as Map?;
            if (data != null) {
              _isRecording = data['isRecording'] == true;
              _status = data['status']?.toString() ?? 'IDLE';
              _elapsedSeconds = (data['elapsedSeconds'] as num?)?.toInt() ?? 0;
              _remainingSeconds = (data['remainingSeconds'] as num?)?.toInt() ?? 0;
              _totalDurationSeconds = (data['totalDurationSeconds'] as num?)?.toInt() ?? 60;
              _activeCameraId = data['cameraId']?.toString() ?? _activeCameraId;
              _activeCameraName = data['cameraName']?.toString() ?? _activeCameraName;
              _activeQuality = data['quality']?.toString() ?? _activeQuality;
              _audioEnabled = data['audioEnabled'] == true;
              _currentFilePath = data['filePath']?.toString();
              notifyListeners();
            }
          } else if (eventType == 'finished') {
            _isRecording = false;
            _status = 'IDLE';
            notifyListeners();
            _finishedController.add(
              RecordingFinishedEvent(
                filePath: event['filePath']?.toString() ?? '',
                fileName: event['fileName']?.toString() ?? 'Video',
                durationSeconds: (event['durationSeconds'] as num?)?.toInt() ?? 0,
                sizeBytes: (event['sizeBytes'] as num?)?.toInt() ?? 0,
                reason: event['reason']?.toString() ?? 'finished',
              ),
            );
            refreshStorageInfo();
          } else if (eventType == 'cancelled') {
            _isRecording = false;
            _status = 'IDLE';
            notifyListeners();
            _cancelledController.add(null);
            refreshStorageInfo();
          } else if (eventType == 'error') {
            _isRecording = false;
            _status = 'IDLE';
            notifyListeners();
            _errorController.add(event['error']?.toString() ?? 'Recording error occurred');
          }
        }
      },
      onError: (dynamic err) {
        debugPrint('Recorder EventChannel error: $err');
      },
    );
  }

  Future<void> refreshStatus() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getRecordingStatus');
      if (res != null) {
        _isRecording = res['isRecording'] == true;
        _status = res['status']?.toString() ?? 'IDLE';
        _elapsedSeconds = (res['elapsedSeconds'] as num?)?.toInt() ?? 0;
        _remainingSeconds = (res['remainingSeconds'] as num?)?.toInt() ?? 0;
        _totalDurationSeconds = (res['totalDurationSeconds'] as num?)?.toInt() ?? 60;
        _activeCameraId = res['cameraId']?.toString() ?? _activeCameraId;
        _activeCameraName = res['cameraName']?.toString() ?? _activeCameraName;
        _activeQuality = res['quality']?.toString() ?? _activeQuality;
        _audioEnabled = res['audioEnabled'] == true;
        _currentFilePath = res['filePath']?.toString();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error getting recording status: $e');
    }
  }

  Future<void> refreshCameras() async {
    try {
      final res = await _methodChannel.invokeListMethod<Map>('getAvailableCameras');
      if (res != null) {
        _availableCameras = res.map((m) => CameraInfo.fromMap(m)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching available cameras: $e');
    }
  }

  Future<void> refreshStorageInfo() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getStorageInfo');
      if (res != null) {
        _storageInfo = Map<String, dynamic>.from(res);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching storage info: $e');
    }
  }

  Future<bool> startRecording({
    required String cameraId,
    required String cameraName,
    required String quality,
    required int durationSeconds,
    required bool audioEnabled,
  }) async {
    try {
      _status = 'STARTING';
      notifyListeners();

      final res = await _methodChannel.invokeMethod<bool>('startRecording', {
        'cameraId': cameraId,
        'cameraName': cameraName,
        'quality': quality,
        'durationSeconds': durationSeconds,
        'audioEnabled': audioEnabled,
      });
      return res == true;
    } catch (e) {
      _status = 'IDLE';
      notifyListeners();
      _errorController.add('Failed to start recording: $e');
      return false;
    }
  }

  Future<bool> stopRecording() async {
    try {
      _status = 'STOPPING';
      notifyListeners();
      final res = await _methodChannel.invokeMethod<bool>('stopRecording');
      return res == true;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      return false;
    }
  }

  Future<bool> cancelRecording() async {
    try {
      _status = 'STOPPING';
      notifyListeners();
      final res = await _methodChannel.invokeMethod<bool>('cancelRecording');
      return res == true;
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
      return false;
    }
  }

  Future<List<RecordingItem>> fetchSavedRecordings() async {
    try {
      final res = await _methodChannel.invokeListMethod<Map>('getSavedRecordings');
      if (res != null) {
        return res.map((m) => RecordingItem.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching saved recordings: $e');
    }
    return [];
  }

  Future<bool> deleteRecording(String filePath) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('deleteRecording', {
        'filePath': filePath,
      });
      await refreshStorageInfo();
      return res == true;
    } catch (e) {
      debugPrint('Error deleting recording: $e');
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> openAppSettings() async {
    try {
      await _methodChannel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('Error opening app settings: $e');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _finishedController.close();
    _errorController.close();
    _cancelledController.close();
    super.dispose();
  }
}
