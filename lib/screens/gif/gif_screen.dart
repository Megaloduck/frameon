import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../models/device_state.dart';
import '../../services/providers.dart';
import '../../services/transport_service.dart';
import '../../services/device_api_extensions.dart'; // WiFi fallback upload
import '../../theme/app_theme.dart';
import '../../widgets/connection_badge.dart';

// ── Provider ──────────────────────────────────────────────────────────────

final gifListProvider = FutureProvider.autoDispose<List<GifEntry>>((ref) async {
  final transport = ref.watch(transportProvider);
  if (!transport.isConnected) return [];
  final raw = await transport.listGifs();
  return raw.map((m) => GifEntry.fromJson(m)).toList();
});

// ── GIF Screen ────────────────────────────────────────────────────────────

class GifScreen extends ConsumerStatefulWidget {
  const GifScreen({super.key});
  @override
  ConsumerState<GifScreen> createState() => _GifScreenState();
}

class _GifScreenState extends ConsumerState<GifScreen> {
  _UploadState _uploadState = const _UploadState.idle();
  double _uploadProgress = 0;
  String? _playingFile;

  @override
  Widget build(BuildContext context) {
    final transport   = ref.watch(transportProvider);
    final isConnected = transport.isConnected;
    final gifList     = ref.watch(gifListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GIF DISPLAY'),
        actions: [
          if (isConnected)
            IconButton(icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh list',
                onPressed: () => ref.invalidate(gifListProvider)),
          const Padding(padding: EdgeInsets.only(right: 16), child: ConnectionBadge()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _UploadCard(
                isConnected: isConnected,
                uploadState: _uploadState,
                uploadProgress: _uploadProgress,
                transportLabel: transport.transportLabel,
                onPick: () => _pickAndUpload(transport),
              ),
              const Gap(28),
              _SectionLabel('STORED ON DEVICE'),
              const Gap(12),
              if (!isConnected)
                _EmptyState(icon: Icons.developer_board_off_outlined,
                    message: 'Connect via USB or WiFi to manage GIFs')
              else
                gifList.when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.gif, strokeWidth: 2))),
                  error: (e, _) => _EmptyState(icon: Icons.error_outline,
                      message: 'Failed to load: $e'),
                  data: (files) => files.isEmpty
                      ? _EmptyState(icon: Icons.gif_box_outlined,
                          message: 'No GIFs stored yet — upload one above')
                      : _GifGrid(files: files, playingFile: _playingFile,
                          onPlay: _playGif, onDelete: _deleteGif),
                ),
              const Gap(24),
              if (isConnected)
                gifList.maybeWhen(
                  data: (files) => _StorageBar(files: files),
                  orElse: () => const SizedBox.shrink(),
                ),
              const Gap(8),
              _InfoBox(transport: transport),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(TransportService transport) async {
    if (!transport.isConnected) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['gif'], withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (file.size > 2 * 1024 * 1024) {
      setState(() => _uploadState = _UploadState.error(
          'File too large (${(file.size/1024).round()}KB). Max ~2MB.'));
      return;
    }

    setState(() {
      _uploadState    = _UploadState.uploading(file.name, 0);
      _uploadProgress = 0;
    });

    try {
      if (transport.transport == ActiveTransport.usb) {
        // USB: chunked upload with progress
        final ok = await transport.uploadGifUsb(
          file.bytes!, file.name,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
        setState(() => _uploadState = ok
            ? _UploadState.success(file.name)
            : _UploadState.error(transport.lastError ?? 'Upload failed'));
      } else {
        // WiFi: multipart HTTP (no per-chunk progress)
        final api = ref.read(deviceApiServiceProvider);
        final ok  = await api.uploadGifFile(file.bytes!, file.name);
        setState(() => _uploadState = ok
            ? _UploadState.success(file.name)
            : _UploadState.error('WiFi upload failed'));
      }
      if (_uploadState is _UploadSuccess) ref.invalidate(gifListProvider);
    } catch (e) {
      setState(() => _uploadState = _UploadState.error('$e'));
    }
  }

  Future<void> _playGif(String filename) async {
    final transport = ref.read(transportProvider);
    await transport.setMode(AppMode.gif);
    await transport.selectGif(filename);
    setState(() => _playingFile = filename);
  }

  Future<void> _deleteGif(String filename) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        title: const Text('Delete GIF', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "$filename"? This cannot be undone.',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.disconnected))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref.read(transportProvider).deleteGif(filename);
    if (ok) {
      if (_playingFile == filename) setState(() => _playingFile = null);
      ref.invalidate(gifListProvider);
    }
  }
}

// ── Upload state ──────────────────────────────────────────────────────────

sealed class _UploadState {
  const _UploadState();
  const factory _UploadState.idle() = _UploadIdle;
  const factory _UploadState.uploading(String name, double progress) = _UploadInProgress;
  const factory _UploadState.success(String name) = _UploadSuccess;
  const factory _UploadState.error(String message) = _UploadError;
}
class _UploadIdle extends _UploadState { const _UploadIdle(); }
class _UploadInProgress extends _UploadState {
  final String name; final double progress;
  const _UploadInProgress(this.name, this.progress);
}
class _UploadSuccess extends _UploadState { final String name; const _UploadSuccess(this.name); }
class _UploadError extends _UploadState { final String message; const _UploadError(this.message); }

// ── Upload card ───────────────────────────────────────────────────────────

class _UploadCard extends StatelessWidget {
  final bool isConnected;
  final _UploadState uploadState;
  final double uploadProgress;
  final String transportLabel;
  final VoidCallback onPick;
  const _UploadCard({required this.isConnected, required this.uploadState,
      required this.uploadProgress, required this.transportLabel, required this.onPick});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isConnected ? AppColors.gif.withOpacity(0.25) : AppColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.gif.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.upload_file_outlined, color: AppColors.gif, size: 22)),
        const Gap(14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Upload GIF',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(isConnected ? 'Via $transportLabel' : 'Connect device first',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      ]),
      const Gap(20),
      switch (uploadState) {
        _UploadIdle()    => _DropZone(isConnected: isConnected, onPick: onPick),
        _UploadInProgress(:final name) => _ProgressView(name: name, progress: uploadProgress),
        _UploadSuccess(:final name) => _SuccessBanner(name: name, onUploadMore: onPick),
        _UploadError(:final message) => _ErrorBanner(message: message, onRetry: onPick),
      },
      const Gap(12),
      const Text('Max ~2MB · GIF auto-loops · Scaled to 32×64 px on device',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]),
  );
}

class _DropZone extends StatelessWidget {
  final bool isConnected; final VoidCallback onPick;
  const _DropZone({required this.isConnected, required this.onPick});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: isConnected ? onPick : null, borderRadius: BorderRadius.circular(10),
    child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: isConnected ? AppColors.gif.withOpacity(0.04) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isConnected
            ? AppColors.gif.withOpacity(0.3) : AppColors.textMuted.withOpacity(0.2))),
      child: Column(children: [
        Icon(Icons.gif_box_outlined, size: 36,
            color: isConnected ? AppColors.gif.withOpacity(0.6) : AppColors.textMuted),
        const Gap(10),
        Text(isConnected ? 'Click to choose a .gif file' : 'Connect device first',
            style: TextStyle(fontSize: 13,
                color: isConnected ? AppColors.gif : AppColors.textMuted,
                fontWeight: FontWeight.w500)),
      ])),
  );
}

class _ProgressView extends StatelessWidget {
  final String name; final double progress;
  const _ProgressView({required this.name, required this.progress});
  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gif)),
      const Gap(12),
      Expanded(child: Text('Uploading $name…',
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis)),
      Text('${(progress * 100).round()}%',
          style: const TextStyle(fontFamily: 'SpaceMono', fontSize: 11, color: AppColors.gif)),
    ]),
    const Gap(10),
    ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress, minHeight: 5,
            color: AppColors.gif, backgroundColor: AppColors.border)),
  ]);
}

class _SuccessBanner extends StatelessWidget {
  final String name; final VoidCallback onUploadMore;
  const _SuccessBanner({required this.name, required this.onUploadMore});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.connected.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.connected.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.check_circle_outline, size: 18, color: AppColors.connected),
      const Gap(10),
      Expanded(child: Text('✓ $name uploaded',
          style: const TextStyle(fontSize: 13, color: AppColors.connected))),
      TextButton(onPressed: onUploadMore,
          style: TextButton.styleFrom(foregroundColor: AppColors.gif,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Upload more', style: TextStyle(fontSize: 12))),
    ]),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.disconnected.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.disconnected.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.error_outline, size: 18, color: AppColors.disconnected),
      const Gap(10),
      Expanded(child: Text(message,
          style: const TextStyle(fontSize: 12, color: AppColors.disconnected))),
      TextButton(onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: AppColors.gif,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Retry', style: TextStyle(fontSize: 12))),
    ]),
  );
}

// ── GIF grid ──────────────────────────────────────────────────────────────

class _GifGrid extends StatelessWidget {
  final List<GifEntry> files; final String? playingFile;
  final ValueChanged<String> onPlay; final ValueChanged<String> onDelete;
  const _GifGrid({required this.files, required this.playingFile,
      required this.onPlay, required this.onDelete});
  @override
  Widget build(BuildContext context) => Column(
      children: files.map((f) => _GifTile(entry: f, isPlaying: f.filename == playingFile,
          onPlay: () => onPlay(f.filename), onDelete: () => onDelete(f.filename))).toList());
}

class _GifTile extends StatelessWidget {
  final GifEntry entry; final bool isPlaying;
  final VoidCallback onPlay; final VoidCallback onDelete;
  const _GifTile({required this.entry, required this.isPlaying,
      required this.onPlay, required this.onDelete});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: isPlaying ? AppColors.gif.withOpacity(0.06) : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isPlaying ? AppColors.gif.withOpacity(0.4) : AppColors.border),
    ),
    child: Row(children: [
      Container(width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.gif.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(isPlaying ? Icons.gif : Icons.gif_box_outlined,
              color: AppColors.gif, size: isPlaying ? 26 : 22)),
      const Gap(14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.displayName, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis),
        Row(children: [
          Text(entry.sizeLabel, style: const TextStyle(
              fontFamily: 'SpaceMono', fontSize: 10, color: AppColors.textMuted)),
          if (isPlaying) ...[
            const Gap(8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.gif.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('PLAYING', style: TextStyle(fontFamily: 'SpaceMono',
                    fontSize: 9, color: AppColors.gif, letterSpacing: 0.8))),
          ],
        ]),
      ])),
      IconButton(onPressed: onPlay,
          icon: Icon(isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
              color: isPlaying ? AppColors.gif : AppColors.textSecondary, size: 26),
          tooltip: isPlaying ? 'Stop' : 'Play on matrix'),
      IconButton(onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
          tooltip: 'Delete'),
    ]),
  );
}

// ── Storage bar ───────────────────────────────────────────────────────────

class _StorageBar extends StatelessWidget {
  final List<GifEntry> files;
  const _StorageBar({required this.files});
  @override
  Widget build(BuildContext context) {
    final totalBytes = files.fold<int>(0, (s, f) => s + f.sizeBytes);
    const maxBytes = 3 * 1024 * 1024;
    final used = (totalBytes / maxBytes).clamp(0.0, 1.0);
    final usedKB = totalBytes < 1024*1024
        ? '${(totalBytes/1024).round()} KB'
        : '${(totalBytes/(1024*1024)).toStringAsFixed(1)} MB';
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SPIFFS storage', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text('$usedKB / ~3 MB', style: const TextStyle(
              fontFamily: 'SpaceMono', fontSize: 11, color: AppColors.textMuted)),
        ]),
        const Gap(8),
        ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: used, minHeight: 6,
                color: used > 0.8 ? AppColors.disconnected : AppColors.gif,
                backgroundColor: AppColors.border)),
        if (used > 0.8)
          const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('Storage nearly full — delete unused GIFs',
                  style: TextStyle(fontSize: 11, color: AppColors.disconnected))),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text; const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.gif, letterSpacing: 1.2));
}

class _EmptyState extends StatelessWidget {
  final IconData icon; final String message;
  const _EmptyState({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Icon(icon, size: 36, color: AppColors.textMuted), const Gap(12),
      Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          textAlign: TextAlign.center),
    ]),
  );
}

class _InfoBox extends StatelessWidget {
  final TransportService transport;
  const _InfoBox({required this.transport});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted), const Gap(6),
        Text('ACTIVE TRANSPORT: ${transport.transportLabel.toUpperCase()}',
            style: const TextStyle(fontFamily: 'SpaceMono', fontSize: 10,
                color: AppColors.textMuted, letterSpacing: 0.8)),
      ]),
      const Gap(8),
      Text(transport.transport == ActiveTransport.usb
          ? 'GIF upload via USB: chunked base64, ~3× faster than WiFi, progress per chunk.'
          : 'GIF upload via WiFi: multipart HTTP. Connect USB for faster uploads.',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.6)),
    ]),
  );
}
