import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/camera_info.dart';
import '../models/recording_item.dart';
import '../services/native_camera_service.dart';
import '../services/settings_service.dart';
import '../widgets/storage_indicator.dart';
import 'gallery_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  final SettingsService settingsService;
  final NativeCameraService cameraService;

  const HomeScreen({
    super.key,
    required this.settingsService,
    required this.cameraService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _listenToEvents();
  }

  void _listenToEvents() {
    widget.cameraService.onRecordingFinished.listen((event) {
      if (mounted) {
        _loadCount();
        _showFinishedDialog(event);
      }
    });

    widget.cameraService.onError.listen((errorMsg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text(errorMsg),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  Future<void> _loadCount() async {
    final list = await widget.cameraService.fetchSavedRecordings();
    if (mounted) {
      setState(() {
        _savedCount = list.length;
      });
    }
  }

  void _showFinishedDialog(RecordingFinishedEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
        title: const Text('Recording Saved!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${event.fileName}'),
            const SizedBox(height: 4),
            Text('Duration: ${event.durationSeconds} seconds'),
            const SizedBox(height: 4),
            Text('Size: ${(event.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
            const SizedBox(height: 12),
            const Text(
              'Your video has been finalized and saved in your device Movies folder.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('View Video'),
            onPressed: () {
              Navigator.pop(ctx);
              _playVideoByPath(event.filePath, event.fileName, event.durationSeconds, event.sizeBytes);
            },
          ),
        ],
      ),
    );
  }

  void _playVideoByPath(String path, String name, int durationSec, int sizeBytes) {
    final item = RecordingItem(
      id: name,
      name: name,
      path: path,
      sizeBytes: sizeBytes,
      durationMs: durationSec * 1000,
      timestamp: DateTime.now(),
      width: 1920,
      height: 1080,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          recording: item,
          onDelete: (p) async {
            final res = await widget.cameraService.deleteRecording(p);
            _loadCount();
            return res;
          },
        ),
      ),
    );
  }

  Future<bool> _checkAndRequestPermissions() async {
    // 1. Camera permission
    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showPermissionAlert('Camera permission is required to record video.');
        return false;
      }
    }

    // 2. Microphone permission if audio enabled
    if (widget.settingsService.audioEnabled) {
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          _showPermissionAlert('Microphone permission is required when audio recording is enabled.');
          return false;
        }
      }
    }

    // 3. Notification permission (Android 13+)
    var notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    return true;
  }

  void _showPermissionAlert(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startRecording() async {
    if (widget.cameraService.isRecording) {
      _openRecordingScreen();
      return;
    }

    // Storage check
    if (widget.cameraService.isLowStorage) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Low Storage Space'),
          content: const Text(
            'Your device has less than 500 MB free space. The recording might be interrupted if disk space runs out. Do you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Permissions check
    final hasPermissions = await _checkAndRequestPermissions();
    if (!hasPermissions) return;

    final settings = widget.settingsService;
    final cameras = widget.cameraService.availableCameras;

    // Pick camera
    CameraInfo? selectedCam;
    if (cameras.isNotEmpty) {
      selectedCam = cameras.firstOrNullWhere((c) => c.id == settings.cameraId) ??
          cameras.firstOrNullWhere((c) => c.lensFacing == settings.cameraFacing) ??
          cameras.first;
    }

    final camId = selectedCam?.id ?? '0';
    final camName = selectedCam?.name ?? 'Rear Camera';
    final quality = settings.quality;
    final durationSeconds = settings.durationSeconds;
    final audio = settings.audioEnabled;

    final started = await widget.cameraService.startRecording(
      cameraId: camId,
      cameraName: camName,
      quality: quality,
      durationSeconds: durationSeconds,
      audioEnabled: audio,
    );

    if (started && mounted) {
      _openRecordingScreen();
    }
  }

  void _openRecordingScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          cameraService: widget.cameraService,
          onFinished: () {
            Navigator.pop(context);
            _loadCount();
          },
        ),
      ),
    );
  }

  void _showCustomDurationDialog() {
    final controller = TextEditingController(
      text: widget.settingsService.customMinutes.toString(),
    );
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Custom Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter recording duration in minutes (1 to 120):'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Minutes',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                  suffixText: 'min',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final mins = int.tryParse(controller.text.trim());
                if (mins == null || mins <= 0 || mins > 120) {
                  setDialogState(() {
                    errorText = 'Enter a valid number between 1 and 120';
                  });
                  return;
                }
                widget.settingsService.setCustomDuration(mins);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settingsService;
    final service = widget.cameraService;

    return ListenableBuilder(
      listenable: Listenable.merge([settings, service]),
      builder: (context, _) {
        final isRecording = service.isRecording;
        final cameras = service.availableCameras;

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.videocam_rounded, size: 28),
                SizedBox(width: 8),
                Text(
                  'BcgCam',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        settingsService: settings,
                        cameraService: service,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              children: [
                // Ongoing recording banner if already recording
                if (isRecording) ...[
                  Card(
                    color: Colors.red.shade900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      onTap: _openRecordingScreen,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.radio_button_checked, color: Colors.white, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Recording in Progress',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Elapsed: ${service.elapsedSeconds}s / ${service.totalDurationSeconds}s (Tap to view)',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Storage Indicator
                StorageIndicator(
                  freeBytes: service.freeStorageBytes,
                  totalBytes: service.totalStorageBytes,
                  path: service.storagePath,
                  onRefresh: () => service.refreshStorageInfo(),
                ),

                const SizedBox(height: 16),

                // Camera Selection Card
                _buildCard(
                  theme: theme,
                  icon: Icons.camera_alt_outlined,
                  title: 'Camera Selection',
                  child: Row(
                    children: [
                      Expanded(
                        child: _cameraOption(
                          theme: theme,
                          label: 'Rear Camera',
                          icon: Icons.camera_rear_rounded,
                          isSelected: settings.cameraFacing == 'back',
                          onTap: () {
                            final backCam = cameras.firstOrNullWhere((c) => c.isBack);
                            settings.setCamera(backCam?.id ?? '0', 'back');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _cameraOption(
                          theme: theme,
                          label: 'Front Camera',
                          icon: Icons.camera_front_rounded,
                          isSelected: settings.cameraFacing == 'front',
                          onTap: () {
                            final frontCam = cameras.firstOrNullWhere((c) => c.isFront);
                            settings.setCamera(frontCam?.id ?? '1', 'front');
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Recording Duration Card
                _buildCard(
                  theme: theme,
                  icon: Icons.timer_outlined,
                  title: 'Recording Duration',
                  trailing: settings.isCustomDuration
                      ? Chip(
                          label: Text('${settings.customMinutes} min'),
                          backgroundColor: theme.colorScheme.primaryContainer,
                          labelStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 11),
                        )
                      : null,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _durationChip(settings, 60, '1 min'),
                      _durationChip(settings, 300, '5 min'),
                      _durationChip(settings, 600, '10 min'),
                      _durationChip(settings, 900, '15 min'),
                      _durationChip(settings, 1800, '30 min'),
                      ChoiceChip(
                        label: Text(settings.isCustomDuration
                            ? 'Custom (${settings.customMinutes}m)'
                            : 'Custom...'),
                        selected: settings.isCustomDuration,
                        onSelected: (val) {
                          _showCustomDurationDialog();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Video Quality Card
                _buildCard(
                  theme: theme,
                  icon: Icons.high_quality_outlined,
                  title: 'Video Quality',
                  child: Row(
                    children: [
                      Expanded(
                        child: _qualityOption(
                          theme: theme,
                          label: '480p SD',
                          isSelected: settings.quality.toLowerCase() == '480p',
                          onTap: () => settings.setQuality('480p'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _qualityOption(
                          theme: theme,
                          label: '720p HD',
                          isSelected: settings.quality.toLowerCase() == '720p',
                          onTap: () => settings.setQuality('720p'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _qualityOption(
                          theme: theme,
                          label: '1080p FHD',
                          isSelected: settings.quality.toLowerCase() == '1080p',
                          onTap: () => settings.setQuality('1080p'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Audio recording toggle & Screen-off badge
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              settings.audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                              color: settings.audioEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                settings.audioEnabled ? 'Audio ON' : 'Audio OFF',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            Switch(
                              value: settings.audioEnabled,
                              onChanged: isRecording ? null : (v) => settings.setAudioEnabled(v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Start Recording Button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red : theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 2,
                    ),
                    icon: Icon(
                      isRecording ? Icons.radio_button_checked : Icons.videocam_rounded,
                      size: 26,
                    ),
                    label: Text(
                      isRecording ? 'View Active Recording' : 'Start Recording',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _startRecording,
                  ),
                ),

                const SizedBox(height: 16),

                // Gallery Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    icon: const Icon(Icons.video_library_rounded),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Recordings Gallery',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        if (_savedCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_savedCount',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GalleryScreen(cameraService: service),
                        ),
                      );
                      _loadCount();
                    },
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _cameraOption({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: widget.cameraService.isRecording ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityOption({
    required ThemeData theme,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: widget.cameraService.isRecording ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _durationChip(SettingsService settings, int seconds, String label) {
    final isSelected = !settings.isCustomDuration && settings.durationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: widget.cameraService.isRecording
          ? null
          : (val) {
              if (val) {
                settings.setPresetDuration(seconds);
              }
            },
    );
  }
}

extension _ListExt<T> on List<T> {
  T? firstOrNullWhere(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
