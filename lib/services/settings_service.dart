import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyCameraId = 'pref_camera_id';
  static const String _keyCameraFacing = 'pref_camera_facing';
  static const String _keyQuality = 'pref_quality';
  static const String _keyDurationSeconds = 'pref_duration_seconds';
  static const String _keyIsCustomDuration = 'pref_is_custom_duration';
  static const String _keyCustomMinutes = 'pref_custom_minutes';
  static const String _keyAudioEnabled = 'pref_audio_enabled';

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _cameraId = '0';
  String _cameraFacing = 'back';
  String _quality = '1080p';
  int _durationSeconds = 60; // default 1 minute
  bool _isCustomDuration = false;
  int _customMinutes = 3;
  bool _audioEnabled = true;

  bool get isInitialized => _isInitialized;
  String get cameraId => _cameraId;
  String get cameraFacing => _cameraFacing;
  String get quality => _quality;
  int get durationSeconds => _isCustomDuration ? (_customMinutes * 60) : _durationSeconds;
  bool get isCustomDuration => _isCustomDuration;
  int get customMinutes => _customMinutes;
  bool get audioEnabled => _audioEnabled;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _cameraId = _prefs.getString(_keyCameraId) ?? '0';
    _cameraFacing = _prefs.getString(_keyCameraFacing) ?? 'back';
    _quality = _prefs.getString(_keyQuality) ?? '1080p';
    _durationSeconds = _prefs.getInt(_keyDurationSeconds) ?? 60;
    _isCustomDuration = _prefs.getBool(_keyIsCustomDuration) ?? false;
    _customMinutes = _prefs.getInt(_keyCustomMinutes) ?? 3;
    _audioEnabled = _prefs.getBool(_keyAudioEnabled) ?? true;

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setCamera(String id, String facing) async {
    _cameraId = id;
    _cameraFacing = facing;
    await _prefs.setString(_keyCameraId, id);
    await _prefs.setString(_keyCameraFacing, facing);
    notifyListeners();
  }

  Future<void> setQuality(String quality) async {
    _quality = quality;
    await _prefs.setString(_keyQuality, quality);
    notifyListeners();
  }

  Future<void> setPresetDuration(int seconds) async {
    _durationSeconds = seconds;
    _isCustomDuration = false;
    await _prefs.setInt(_keyDurationSeconds, seconds);
    await _prefs.setBool(_keyIsCustomDuration, false);
    notifyListeners();
  }

  Future<void> setCustomDuration(int minutes) async {
    _customMinutes = minutes;
    _isCustomDuration = true;
    _durationSeconds = minutes * 60;
    await _prefs.setInt(_keyCustomMinutes, minutes);
    await _prefs.setBool(_keyIsCustomDuration, true);
    await _prefs.setInt(_keyDurationSeconds, minutes * 60);
    notifyListeners();
  }

  Future<void> setAudioEnabled(bool enabled) async {
    _audioEnabled = enabled;
    await _prefs.setBool(_keyAudioEnabled, enabled);
    notifyListeners();
  }
}
