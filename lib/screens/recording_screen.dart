import 'package:flutter/material.dart';
import '../services/native_camera_service.dart';

class RecordingScreen extends StatefulWidget {
  final NativeCameraService cameraService;
  final VoidCallback onFinished;

  const RecordingScreen({
    super.key,
    required this.cameraService,
    required this.onFinished,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final h = m ~/ 60;
    if (h > 0) {
      final remM = m % 60;
      return '${h.toString().padLeft(2, '0')}:${remM.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Recording?'),
        content: const Text(
          'Are you sure you want to cancel? The video recorded so far will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Recording'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard Recording'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.cameraService.cancelRecording();
      widget.onFinished();
    }
  }

  void _stopRecording() async {
    await widget.cameraService.stopRecording();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = widget.cameraService;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final elapsed = service.elapsedSeconds;
        final remaining = service.remainingSeconds;
        final total = service.totalDurationSeconds;
        final progress = (total > 0) ? (elapsed / total).clamp(0.0, 1.0) : 0.0;

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Active Recording'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Minimize View',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Pulsing recording badge
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15 + (_pulseController.value * 0.15)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.5 + (_pulseController.value * 0.5)),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.8),
                                    blurRadius: 6 + (_pulseController.value * 4),
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              service.status == 'STARTING' ? 'INITIALIZING CAMERA...' : 'RECORDING ACTIVE',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const Spacer(),

                  // Circular progress timer ring
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 8,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(elapsed),
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '-${_formatTime(remaining)} remaining',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Target: ${_formatTime(total)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Spec chips
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _specChip(Icons.camera_alt_outlined, service.activeCameraName, theme),
                      _specChip(Icons.video_settings_outlined, service.activeQuality, theme),
                      _specChip(
                        service.audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                        service.audioEnabled ? 'Audio ON' : 'Audio OFF',
                        theme,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Screen-off reassuring banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.screen_lock_portrait_rounded, color: theme.colorScheme.primary, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You can safely turn off your screen or minimize the app. Recording will continue uninterrupted in the background.',
                            style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Stop & Cancel buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _confirmCancel,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.stop_circle_rounded, size: 26),
                          label: const Text('Stop Recording', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _stopRecording,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _specChip(IconData icon, String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
