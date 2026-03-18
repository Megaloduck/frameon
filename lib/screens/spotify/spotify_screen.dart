import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../models/device_state.dart';
import '../../services/providers.dart';
import '../../services/spotify_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_badge.dart';

class SpotifyScreen extends ConsumerStatefulWidget {
  const SpotifyScreen({super.key});

  @override
  ConsumerState<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends ConsumerState<SpotifyScreen> {
  bool _autoPush = false;
  String? _pushResult;

  @override
  Widget build(BuildContext context) {
    final spotify = ref.watch(spotifyServiceProvider);
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SPOTIFY'),
        actions: [
          if (spotify.auth == SpotifyAuthState.loggedIn)
            TextButton.icon(
              onPressed: () => ref.read(spotifyServiceProvider.notifier).logout(),
              icon: const Icon(Icons.logout, size: 16, color: AppColors.textMuted),
              label: const Text('Log out',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          const Padding(padding: EdgeInsets.only(right: 16), child: ConnectionBadge()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: switch (spotify.auth) {
              SpotifyAuthState.loggedOut ||
              SpotifyAuthState.error =>
                _LoginView(
                  errorMessage: spotify.errorMessage,
                  onLogin: () =>
                      ref.read(spotifyServiceProvider.notifier).login(),
                ),
              SpotifyAuthState.authorizing => _AuthorizingView(),
              SpotifyAuthState.loggedIn => Column(
                  children: [
                    // ── Now Playing ────────────────────────────────────
                    _NowPlayingCard(
                      spotify: spotify,
                      onPlay: () =>
                          ref.read(spotifyServiceProvider.notifier).play(),
                      onPause: () =>
                          ref.read(spotifyServiceProvider.notifier).pause(),
                      onNext: () =>
                          ref.read(spotifyServiceProvider.notifier).next(),
                      onPrev: () =>
                          ref.read(spotifyServiceProvider.notifier).previous(),
                    ),
                    const Gap(24),

                    // ── Matrix push ────────────────────────────────────
                    _MatrixPushCard(
                      spotify: spotify,
                      isDeviceConnected: isConnected,
                      autoPush: _autoPush,
                      pushResult: _pushResult,
                      onAutoPushToggle: (v) {
                        setState(() => _autoPush = v);
                        if (v && spotify.track != null) _pushToMatrix(spotify);
                      },
                      onManualPush: () => _pushToMatrix(spotify),
                    ),
                    const Gap(24),

                    // ── Album art preview ──────────────────────────────
                    if (spotify.albumArtProcessed != null)
                      _AlbumArtPreview(
                          artBytes: spotify.albumArtProcessed!),
                    const Gap(24),

                    // ── Setup note ─────────────────────────────────────
                    _SetupNote(),
                  ],
                ),
            },
          ),
        ),
      ),
    );
  }

  // Auto-push whenever track changes
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoPush) {
      final spotify = ref.read(spotifyServiceProvider);
      if (spotify.track != null) _pushToMatrix(spotify);
    }
  }

  Future<void> _pushToMatrix(SpotifyServiceState spotify) async {
    if (!ref.read(deviceStateProvider).isConnected) return;
    if (spotify.track == null) return;

    final api = ref.read(deviceApiServiceProvider);
    try {
      await api.setMode(AppMode.spotify);
      await api.pushSpotifyState(
        trackName: spotify.track!.trackName,
        artistName: spotify.track!.artistName,
        isPlaying: spotify.track!.isPlaying,
        albumArtJpeg: spotify.albumArtProcessed,
      );
      if (mounted) setState(() => _pushResult = '✓ Pushed to matrix');
    } catch (e) {
      if (mounted) setState(() => _pushResult = '✗ Push failed: $e');
    }
  }
}

// ── Login view ────────────────────────────────────────────────────────────

class _LoginView extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback onLogin;

  const _LoginView({this.errorMessage, required this.onLogin});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Gap(32),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.spotify.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.music_note, color: AppColors.spotify, size: 36),
          ),
          const Gap(24),
          const Text(
            'Connect Spotify',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Gap(8),
          const Text(
            'Authorize Frameon to read your playback\nand show it on the LED matrix.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          if (errorMessage != null) ...[
            const Gap(16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.disconnected.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.disconnected.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    size: 16, color: AppColors.disconnected),
                const Gap(8),
                Expanded(
                  child: Text(errorMessage!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.disconnected)),
                ),
              ]),
            ),
          ],
          const Gap(32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onLogin,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.spotify,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Connect with Spotify'),
            ),
          ),
          const Gap(16),
          const Text(
            'You\'ll be redirected to Spotify to authorize.\n'
            'Frameon only requests read + playback control permissions.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      );
}

class _AuthorizingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Column(
          children: [
            CircularProgressIndicator(
                color: AppColors.spotify, strokeWidth: 2),
            Gap(20),
            Text(
              'Waiting for Spotify authorization…',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            Gap(8),
            Text(
              'Complete the login in your browser,\nthen return to Frameon.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
}

// ── Now playing card ──────────────────────────────────────────────────────

class _NowPlayingCard extends StatelessWidget {
  final SpotifyServiceState spotify;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const _NowPlayingCard({
    required this.spotify,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    final track = spotify.track;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: track != null && track.isPlaying
              ? AppColors.spotify.withOpacity(0.4)
              : AppColors.border,
        ),
      ),
      child: track == null
          ? const _NothingPlaying()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + refresh
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: track.isPlaying
                            ? AppColors.spotify
                            : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      track.isPlaying ? 'NOW PLAYING' : 'PAUSED',
                      style: TextStyle(
                        fontFamily: 'SpaceMono',
                        fontSize: 10,
                        color: track.isPlaying
                            ? AppColors.spotify
                            : AppColors.textMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Consumer(builder: (context, ref, _) => IconButton(
                      onPressed: () =>
                          ref.read(spotifyServiceProvider.notifier).refreshNow(),
                      icon: const Icon(Icons.refresh,
                          size: 18, color: AppColors.textMuted),
                      tooltip: 'Refresh',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )),
                  ],
                ),
                const Gap(14),

                // Track info
                Text(
                  track.trackName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(4),
                Text(
                  track.artistName,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                if (track.albumName.isNotEmpty) ...[
                  const Gap(2),
                  Text(
                    track.albumName,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
                const Gap(16),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: track.progressFraction,
                    minHeight: 3,
                    color: AppColors.spotify,
                    backgroundColor: AppColors.border,
                  ),
                ),
                const Gap(4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(track.progressLabel,
                        style: const TextStyle(
                            fontFamily: 'SpaceMono',
                            fontSize: 10,
                            color: AppColors.textMuted)),
                  ],
                ),
                const Gap(16),

                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SpotifyBtn(
                        icon: Icons.skip_previous, onTap: onPrev, size: 28),
                    const Gap(16),
                    GestureDetector(
                      onTap: track.isPlaying ? onPause : onPlay,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: AppColors.spotify,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          track.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 28,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Gap(16),
                    _SpotifyBtn(
                        icon: Icons.skip_next, onTap: onNext, size: 28),
                  ],
                ),
              ],
            ),
    );
  }

  // Workaround since we can't use ref in a non-Consumer widget
  void ref_read_refresh(BuildContext context) {
    // This is called via the refresh button — parent widget handles it
  }
}

class _SpotifyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _SpotifyBtn(
      {required this.icon, required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: size, color: AppColors.textSecondary),
        ),
      );
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.music_off_outlined,
                size: 36, color: AppColors.textMuted),
            Gap(12),
            Text(
              'Nothing playing',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            Gap(4),
            Text(
              'Start playing something in Spotify',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
}

// ── Matrix push card ──────────────────────────────────────────────────────

class _MatrixPushCard extends StatelessWidget {
  final SpotifyServiceState spotify;
  final bool isDeviceConnected;
  final bool autoPush;
  final String? pushResult;
  final ValueChanged<bool> onAutoPushToggle;
  final VoidCallback onManualPush;

  const _MatrixPushCard({
    required this.spotify,
    required this.isDeviceConnected,
    required this.autoPush,
    required this.pushResult,
    required this.onAutoPushToggle,
    required this.onManualPush,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.developer_board_outlined,
                    size: 18, color: AppColors.spotify),
                const Gap(10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-push to matrix',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                      Text('Sends track info on every song change',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Switch(
                  value: autoPush,
                  activeColor: AppColors.spotify,
                  onChanged: isDeviceConnected ? onAutoPushToggle : null,
                ),
              ],
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDeviceConnected && spotify.track != null
                    ? onManualPush
                    : null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.spotify),
                  foregroundColor: AppColors.spotify,
                ),
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Push current track now'),
              ),
            ),
            if (!isDeviceConnected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Connect to ESP32 in Setup to push to matrix',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            if (pushResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  pushResult!,
                  style: TextStyle(
                    fontSize: 12,
                    color: pushResult!.startsWith('✓')
                        ? AppColors.connected
                        : AppColors.disconnected,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
}

// ── Album art preview ─────────────────────────────────────────────────────

class _AlbumArtPreview extends StatelessWidget {
  final Uint8List artBytes;

  const _AlbumArtPreview({required this.artBytes});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROCESSED ALBUM ART',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.spotify,
                    letterSpacing: 1.2,
                  ),
            ),
            const Gap(12),
            Row(
              children: [
                // Scaled preview
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      artBytes,
                      width: 128,
                      height: 64,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none, // pixelated = authentic
                    ),
                  ),
                ),
                const Gap(16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('64 × 32 pixels',
                          style: TextStyle(
                              fontFamily: 'SpaceMono',
                              fontSize: 12,
                              color: AppColors.textPrimary)),
                      Gap(4),
                      Text(
                        'Cropped to square, resized, and JPEG-encoded.\nSent as base64 to ESP32.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

// ── Setup note ────────────────────────────────────────────────────────────

class _SetupNote extends StatelessWidget {
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
              Text('DEVELOPER SETUP REQUIRED',
                  style: TextStyle(
                      fontFamily: 'SpaceMono',
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8)),
            ]),
            Gap(8),
            Text(
              '1. Create a Spotify app at developer.spotify.com\n'
              '2. Add redirect URI: frameon://spotify-callback\n'
              '3. Replace YOUR_SPOTIFY_CLIENT_ID in spotify_service.dart\n'
              '4. For desktop: add platform-specific deep link config\n'
              '   (android/ios/windows/macos manifest entries)',
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
