import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../models/device_state.dart';
import '../../services/providers.dart';
import '../../services/device_api_extensions.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_badge.dart';

// ── Providers ─────────────────────────────────────────────────────────────

final gifListProvider = FutureProvider.autoDispose<List<GifEntry>>((ref) async {
  final api = ref.watch(deviceApiServiceProvider);
  if (!api.deviceState.isConnected) return [];
  return api.fetchGifList();
});

// ── GIF Screen ────────────────────────────────────────────────────────────

class GifScreen extends ConsumerStatefulWidget {
  const GifScreen({super.key});

  @override
  ConsumerState<GifScreen> createState() => _GifScreenState();
}

class _GifScreenState extends ConsumerState<GifScreen> {
  _UploadState _uploadState = const _UploadState.idle();
  String? _playingFile;

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(deviceStateProvider).isConnected;
    final gifList = ref.watch(gifListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GIF DISPLAY'),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Refresh list',
              onPressed: () => ref.invalidate(gifListProvider),
            ),
          const Padding(padding: EdgeInsets.only(right: 16), child: ConnectionBadge()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Upload card ───────────────────────────────────────────
                _UploadCard(
                  isConnected: isConnected,
                  uploadState: _uploadState,
                  onPick: _pickAndUpload,
                ),
                const Gap(28),

                // ── Stored GIFs ───────────────────────────────────────────
                _SectionLabel('STORED ON DEVICE'),
                const Gap(12),

                if (!isConnected)
                  _EmptyState(
                    icon: Icons.developer_board_off_outlined,
                    message: 'Connect to your ESP32 to manage GIFs',
                  )
                else
                  gifList.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                            color: AppColors.gif, strokeWidth: 2),
                      ),
                    ),
                    error: (e, _) => _EmptyState(
                      icon: Icons.error_outline,
                      message: 'Failed to load GIF list: $e',
                    ),
                    data: (files) => files.isEmpty
                        ? _EmptyState(
                            icon: Icons.gif_box_outlined,
                            message: 'No GIFs stored yet — upload one above',
                          )
                        : _GifGrid(
                            files: files,
                            playingFile: _playingFile,
                            onPlay: (f) => _playGif(f),
                            onDelete: (f) => _deleteGif(f),
                          ),
                  ),
                const Gap(24),

                // ── SPIFFS hint ───────────────────────────────────────────
                if (isConnected)
                  gifList.maybeWhen(
                    data: (files) => _StorageBar(files: files),
                    orElse: () => const SizedBox.shrink(),
                  ),
                const Gap(8),
                _InfoBox(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    if (!ref.read(deviceStateProvider).isConnected) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    // Validate size — SPIFFS typically 1–4MB total
    if (file.size > 2 * 1024 * 1024) {
      setState(() => _uploadState = _UploadState.error(
          'File too large (${(file.size / 1024).round()}KB). Max ~2MB for SPIFFS.'));
      return;
    }

    setState(() => _uploadState = _UploadState.uploading(file.name, 0));

    try {
      final api = ref.read(deviceApiServiceProvider);
      final ok = await api.uploadGifFile(file.bytes!, file.name);

      if (ok) {
        setState(() => _uploadState = _UploadState.success(file.name));
        ref.invalidate(gifListProvider);
      } else {
        setState(() =>
            _uploadState = _UploadState.error('Upload failed — check device connection'));
      }
    } catch (e) {
      setState(
          () => _uploadState = _UploadState.error('Upload error: $e'));
    }
  }

  Future<void> _playGif(String filename) async {
    final api = ref.read(deviceApiServiceProvider);
    await api.setMode(AppMode.gif);
    await api.selectGif(filename);
    setState(() => _playingFile = filename);
  }

  Future<void> _deleteGif(String filename) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete GIF',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "$filename" from device storage? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.disconnected)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final api = ref.read(deviceApiServiceProvider);
    final ok = await api.deleteGif(filename);
    if (ok) {
      if (_playingFile == filename) setState(() => _playingFile = null);
      ref.invalidate(gifListProvider);
    }
  }
}

// ── Upload card ───────────────────────────────────────────────────────────

sealed class _UploadState {
  const _UploadState();
  const factory _UploadState.idle() = _UploadIdle;
  const factory _UploadState.uploading(String name, double progress) =
      _UploadInProgress;
  const factory _UploadState.success(String name) = _UploadSuccess;
  const factory _UploadState.error(String message) = _UploadError;
}

class _UploadIdle extends _UploadState {
  const _UploadIdle();
}

class _UploadInProgress extends _UploadState {
  final String name;
  final double progress;
  const _UploadInProgress(this.name, this.progress);
}

class _UploadSuccess extends _UploadState {
  final String name;
  const _UploadSuccess(this.name);
}

class _UploadError extends _UploadState {
  final String message;
  const _UploadError(this.message);
}

class _UploadCard extends StatelessWidget {
  final bool isConnected;
  final _UploadState uploadState;
  final VoidCallback onPick;

  const _UploadCard({
    required this.isConnected,
    required this.uploadState,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? AppColors.gif.withOpacity(0.25)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.gif.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.upload_file_outlined,
                    color: AppColors.gif, size: 22),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Upload GIF',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(
                    'Send a .gif file to ESP32 SPIFFS',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const Gap(20),

          // State display
          switch (uploadState) {
            _UploadIdle() => _DropZone(
                isConnected: isConnected,
                onPick: onPick,
              ),
            _UploadInProgress(:final name) => _ProgressIndicator(name: name),
            _UploadSuccess(:final name) => _SuccessBanner(name: name, onUploadMore: onPick),
            _UploadError(:final message) => _ErrorBanner(message: message, onRetry: onPick),
          },

          const Gap(12),
          const Text(
            'Max ~2MB per file · GIF auto-loops · Scaled to 32×64 px on device',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onPick;

  const _DropZone({required this.isConnected, required this.onPick});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: isConnected ? onPick : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: isConnected
                ? AppColors.gif.withOpacity(0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isConnected
                  ? AppColors.gif.withOpacity(0.3)
                  : AppColors.textMuted.withOpacity(0.2),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.gif_box_outlined,
                size: 36,
                color: isConnected
                    ? AppColors.gif.withOpacity(0.6)
                    : AppColors.textMuted,
              ),
              const Gap(10),
              Text(
                isConnected ? 'Click to choose a .gif file' : 'Connect device first',
                style: TextStyle(
                  fontSize: 13,
                  color: isConnected ? AppColors.gif : AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ProgressIndicator extends StatelessWidget {
  final String name;
  const _ProgressIndicator({required this.name});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gif),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  'Uploading $name…',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Gap(10),
          const LinearProgressIndicator(
            color: AppColors.gif,
            backgroundColor: AppColors.border,
          ),
        ],
      );
}

class _SuccessBanner extends StatelessWidget {
  final String name;
  final VoidCallback onUploadMore;

  const _SuccessBanner({required this.name, required this.onUploadMore});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.connected.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.connected.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 18, color: AppColors.connected),
            const Gap(10),
            Expanded(
              child: Text(
                '✓ $name uploaded successfully',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.connected),
              ),
            ),
            TextButton(
              onPressed: onUploadMore,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.gif,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Upload more', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.disconnected.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.disconnected.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                size: 18, color: AppColors.disconnected),
            const Gap(10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.disconnected),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.gif,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

// ── GIF grid ──────────────────────────────────────────────────────────────

class _GifGrid extends StatelessWidget {
  final List<GifEntry> files;
  final String? playingFile;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onDelete;

  const _GifGrid({
    required this.files,
    required this.playingFile,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: files
            .map((f) => _GifTile(
                  entry: f,
                  isPlaying: f.filename == playingFile,
                  onPlay: () => onPlay(f.filename),
                  onDelete: () => onDelete(f.filename),
                ))
            .toList(),
      );
}

class _GifTile extends StatelessWidget {
  final GifEntry entry;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _GifTile({
    required this.entry,
    required this.isPlaying,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isPlaying
              ? AppColors.gif.withOpacity(0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPlaying
                ? AppColors.gif.withOpacity(0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            // Icon / playing indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.gif.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isPlaying
                  ? const Icon(Icons.gif, color: AppColors.gif, size: 26)
                  : const Icon(Icons.gif_box_outlined,
                      color: AppColors.gif, size: 22),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        entry.sizeLabel,
                        style: const TextStyle(
                            fontFamily: 'SpaceMono',
                            fontSize: 10,
                            color: AppColors.textMuted),
                      ),
                      if (isPlaying) ...[
                        const Gap(8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.gif.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PLAYING',
                            style: TextStyle(
                              fontFamily: 'SpaceMono',
                              fontSize: 9,
                              color: AppColors.gif,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Play button
            IconButton(
              onPressed: onPlay,
              icon: Icon(
                isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
                color: isPlaying ? AppColors.gif : AppColors.textSecondary,
                size: 26,
              ),
              tooltip: isPlaying ? 'Stop' : 'Play on matrix',
            ),
            // Delete
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textMuted, size: 20),
              tooltip: 'Delete',
            ),
          ],
        ),
      );
}

// ── Storage bar ───────────────────────────────────────────────────────────

class _StorageBar extends StatelessWidget {
  final List<GifEntry> files;

  const _StorageBar({required this.files});

  @override
  Widget build(BuildContext context) {
    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    const maxBytes = 3 * 1024 * 1024; // ~3MB SPIFFS for GIFs
    final used = (totalBytes / maxBytes).clamp(0.0, 1.0);
    final usedKB = totalBytes < 1024 * 1024
        ? '${(totalBytes / 1024).round()} KB'
        : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SPIFFS storage',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(
                '$usedKB / ~3 MB',
                style: const TextStyle(
                    fontFamily: 'SpaceMono',
                    fontSize: 11,
                    color: AppColors.textMuted),
              ),
            ],
          ),
          const Gap(8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 6,
              color: used > 0.8 ? AppColors.disconnected : AppColors.gif,
              backgroundColor: AppColors.border,
            ),
          ),
          if (used > 0.8)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Storage nearly full — delete unused GIFs',
                style: TextStyle(fontSize: 11, color: AppColors.disconnected),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.gif,
              letterSpacing: 1.2,
            ),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.textMuted),
            const Gap(12),
            Text(message,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted),
                textAlign: TextAlign.center),
          ],
        ),
      );
}

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(children: [
              Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
              Gap(6),
              Text('ESP32 FIRMWARE REQUIREMENTS',
                  style: TextStyle(
                      fontFamily: 'SpaceMono',
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8)),
            ]),
            Gap(8),
            Text(
              'POST /api/gif/upload — multipart/form-data, field "file"\n'
              'GET  /api/gif/list   — returns {"files":[{"name":"…","size":N}]}\n'
              'POST /api/gif/select — body {"file":"name.gif"}\n'
              'DELETE /api/gif/delete — body {"file":"name.gif"}',
              style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.8),
            ),
          ],
        ),
      );
}
