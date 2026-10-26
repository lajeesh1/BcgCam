import 'package:flutter/material.dart';
import '../services/native_camera_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final NativeCameraService cameraService;

  const SettingsScreen({
    super.key,
    required this.settingsService,
    required this.cameraService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isIgnoringBattery = false;

  @override
  void initState() {
    super.initState();
    _checkBatteryStatus();
  }

  Future<void> _checkBatteryStatus() async {
    final status = await widget.cameraService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isIgnoringBattery = status;
      });
    }
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
              child: const Text('Save'),
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
    final cameras = widget.cameraService.availableCameras;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildSectionHeader(theme, 'Camera & Video Options'),
              // Camera selection
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.camera_alt_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Camera Selection', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Rear Camera'),
                            selected: settings.cameraFacing == 'back',
                            onSelected: (val) {
                              if (val) {
                                final backCam = cameras.where((c) => c.isBack).firstOrNull;
                                settings.setCamera(backCam?.id ?? '0', 'back');
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Front Camera'),
                            selected: settings.cameraFacing == 'front',
                            onSelected: (val) {
                              if (val) {
                                final frontCam = cameras.where((c) => c.isFront).firstOrNull;
                                settings.setCamera(frontCam?.id ?? '1', 'front');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      // Video Quality
                      Row(
                        children: [
                          Icon(Icons.high_quality_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Video Quality', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: ['480p', '720p', '1080p'].map((q) {
                          final isSelected = settings.quality.toLowerCase() == q.toLowerCase();
                          return ChoiceChip(
                            label: Text(q == '1080p' ? '1080p Full HD' : (q == '720p' ? '720p HD' : '480p SD')),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                settings.setQuality(q);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      // Audio recording toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Record Audio', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Include microphone audio track with video'),
                        secondary: Icon(
                          settings.audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                          color: settings.audioEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                        value: settings.audioEnabled,
                        onChanged: (val) {
                          settings.setAudioEnabled(val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(theme, 'Recording Duration'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Auto-Stop Duration', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
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
                                ? 'Custom (${settings.customMinutes} min)'
                                : 'Custom...'),
                            selected: settings.isCustomDuration,
                            onSelected: (val) {
                              _showCustomDurationDialog();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(theme, 'Background & Screen-Off Guide'),
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_clock_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Screen-Off Recording',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '• How it works: A dedicated Android Foreground Service with Camera & Microphone types keeps recording alive.\n'
                        '• Screen Off: Once recording starts, you can safely turn off your display or minimize the app.\n'
                        '• Notification: An ongoing notification with a live timer and "Stop Recording" button is maintained at all times.\n'
                        '• Privacy: Android displays a green camera indicator in the status bar while recording as required by Android OS privacy policies.',
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(theme, 'Battery & OEM Restrictions'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isIgnoringBattery ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded,
                            color: _isIgnoringBattery ? Colors.green : Colors.amber.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Battery Optimization',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isIgnoringBattery ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isIgnoringBattery ? 'Unrestricted' : 'Optimized',
                              style: TextStyle(
                                color: _isIgnoringBattery ? Colors.green.shade800 : Colors.amber.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Some manufacturers (Samsung, Xiaomi, Oppo) aggressively kill background services when the screen is turned off. To prevent interruptions during long recordings, exempt this app from battery optimization.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.battery_saver_rounded),
                        label: const Text('Open Battery Optimization Settings'),
                        onPressed: () async {
                          await widget.cameraService.requestIgnoreBatteryOptimizations();
                          _checkBatteryStatus();
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(theme, 'Storage & Permissions'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Storage Location', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.cameraService.storagePath,
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings_applications_outlined),
                        label: const Text('System App Permissions'),
                        onPressed: () => widget.cameraService.openAppSettings(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(theme, 'About'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(Icons.person_outline_rounded, color: theme.colorScheme.primary),
                  title: const Text(
                    'About Developer',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                        content: const Text(
                          'Lajeesh',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        actionsAlignment: MainAxisAlignment.center,
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _durationChip(SettingsService settings, int seconds, String label) {
    final isSelected = !settings.isCustomDuration && settings.durationSeconds == seconds;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          settings.setPresetDuration(seconds);
        }
      },
    );
  }
}
