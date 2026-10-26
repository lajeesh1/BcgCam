import 'package:flutter/material.dart';

class StorageIndicator extends StatelessWidget {
  final int freeBytes;
  final int totalBytes;
  final String path;
  final VoidCallback? onRefresh;

  const StorageIndicator({
    super.key,
    required this.freeBytes,
    required this.totalBytes,
    required this.path,
    this.onRefresh,
  });

  bool get isLowStorage => freeBytes > 0 && freeBytes < 500 * 1024 * 1024; // < 500 MB

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedBytes = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : 0;
    final usedRatio = (totalBytes > 0) ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

    return Card(
      elevation: 0,
      color: isLowStorage
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isLowStorage ? theme.colorScheme.error : theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLowStorage ? Icons.warning_amber_rounded : Icons.sd_storage_rounded,
                  color: isLowStorage ? theme.colorScheme.error : theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isLowStorage ? 'Storage Space Warning' : 'Device Storage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isLowStorage ? theme.colorScheme.error : null,
                  ),
                ),
                const Spacer(),
                if (onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: onRefresh,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Refresh Storage',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usedRatio,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isLowStorage ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatBytes(freeBytes)} free of ${_formatBytes(totalBytes)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${(usedRatio * 100).toStringAsFixed(0)}% used',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (isLowStorage) ...[
              const SizedBox(height: 8),
              Text(
                'Available storage is very low (< 500 MB). Recording may stop automatically if disk space runs out.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Save Path: $path',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
