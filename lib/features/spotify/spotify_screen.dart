import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_uuids.dart';
import '../ui/connection_status.dart';
import '../ui/theme_switcher.dart';
import '../ui/led_matrix_preview.dart';

// ── Mock data (replace with real Spotify API responses) ───────────────────────

class SpotifyTrack {
  final String title;
  final String artist;
  final String album;
  final String? albumArtUrl;
  final int durationMs;
  final int progressMs;
  final bool isPlaying;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtUrl,
    required this.durationMs,
    required this.progressMs,
    required this.isPlaying,
  });

  String formatDuration(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String get progressStr => formatDuration(progressMs);
  String get durationStr => formatDuration(durationMs);
}

const _kMockTrack = SpotifyTrack(
  title: 'Redbone',
  artist: 'Childish Gambino',
  album: 'Awaken, My Love!',
  durationMs: 327000,
  progressMs: 84000,
  isPlaying: true,
);

// ── Display layout options ────────────────────────────────────────────────────

enum SpotifyLayout { artOnly, textOnly, artAndText, scrollingText }
enum ScrollSpeed  { slow, medium, fast }

// ── Screen ────────────────────────────────────────────────────────────────────

class SpotifyScreen extends ConsumerStatefulWidget {
  const SpotifyScreen({super.key});

  @override
  ConsumerState<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends ConsumerState<SpotifyScreen>
    with SingleTickerProviderStateMixin {
  SpotifyTrack _track = _kMockTrack;
  bool _connected    = false;
  bool _sendingToDevice = false;

  SpotifyLayout _layout      = SpotifyLayout.artAndText;
  ScrollSpeed   _scrollSpeed = ScrollSpeed.medium;
  bool  _showProgress = true;
  bool  _showArtist   = true;
  double _brightness  = 0.85;

  late final AnimationController _scrollCtrl;
  late Timer _progressTimer;
  int _simulatedProgress = _kMockTrack.progressMs;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_track.isPlaying && mounted) {
        setState(() {
          _simulatedProgress =
              (_simulatedProgress + 1000).clamp(0, _track.durationMs);
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _progressTimer.cancel();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() => _track = SpotifyTrack(
      title: _track.title,
      artist: _track.artist,
      album: _track.album,
      durationMs: _track.durationMs,
      progressMs: _simulatedProgress,
      isPlaying: !_track.isPlaying,
    ));
  }

  void _skipNext()     => setState(() => _simulatedProgress = 0);
  void _skipPrevious() => setState(() => _simulatedProgress = 0);

  Future<void> _toggleSpotifyMode() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (!_sendingToDevice) {
      if (bleManager.state != FrameonConnectionState.connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No device connected.',
              style: TextStyle(fontFamily: 'monospace')),
        ));
        return;
      }
      try {
        await bleService.setMode(kModeSpotify);
        setState(() => _sendingToDevice = true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'monospace')),
        ));
      }
    } else {
      setState(() => _sendingToDevice = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors     = AppColors.of(context);
    final bleManager = ref.watch(bleManagerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(children: [
        _buildHeader(colors),
        ConnectionStatusBar(
          manager: bleManager,
          onTap: () => DeviceScannerSheet.show(context, bleManager),
        ),
        Expanded(
          child: Row(children: [
            Expanded(child: _buildMainPanel(colors)),
            _buildRightPanel(colors),
          ]),
        ),
        _buildStatusBar(colors),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader(AppColors colors) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.arrow_back_ios, color: colors.textMuted, size: 16),
        ),
        const SizedBox(width: 16),
        Text('SPOTIFY', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: colors.textPrimary, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        Text('NOW PLAYING', style: TextStyle(
          fontSize: 11, color: colors.textMuted,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        _buildConnectButton(colors),
        const SizedBox(width: 8),
        const ThemeToggleButton(),
      ]),
    );
  }

  Widget _buildConnectButton(AppColors colors) {
    final spotify = colors.accentSpotify;
    return GestureDetector(
      onTap: () => setState(() => _connected = !_connected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: _connected ? spotify.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: _connected ? spotify : colors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_connected)
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: spotify, shape: BoxShape.circle),
            ),
          Text(
            _connected ? 'CONNECTED' : 'CONNECT SPOTIFY',
            style: TextStyle(
              fontSize: 10,
              color: _connected ? spotify : colors.textSecondary,
              letterSpacing: 1, fontFamily: 'monospace',
            ),
          ),
        ]),
      ),
    );
  }

  // ── Main panel ────────────────────────────────────────────────

  Widget _buildMainPanel(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Expanded(child: _buildNowPlayingCard(colors)),
        const SizedBox(height: 20),
        _buildMatrixPreview(colors),
      ]),
    );
  }

  Widget _buildNowPlayingCard(AppColors colors) {
    final spotify = colors.accentSpotify;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // Album art
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: _track.albumArtUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(
                        _track.albumArtUrl!, fit: BoxFit.cover),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note, color: spotify, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          _connected ? 'NO ALBUM ART' : 'NOT CONNECTED',
                          style: TextStyle(
                            fontSize: 10, color: colors.textMuted,
                            fontFamily: 'monospace', letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Track info
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _track.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                  color: colors.textPrimary, letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${_track.artist} · ${_track.album}',
                style: TextStyle(
                  fontSize: 11, color: colors.textSecondary,
                  fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _buildProgressBar(colors),
              const SizedBox(height: 16),
              _buildControls(colors),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildProgressBar(AppColors colors) {
    final spotify  = colors.accentSpotify;
    final progress = _track.durationMs > 0
        ? _simulatedProgress / _track.durationMs
        : 0.0;

    return Column(children: [
      Stack(children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: spotify,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Text(_track.formatDuration(_simulatedProgress), style: TextStyle(
          fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
        )),
        const Spacer(),
        Text(_track.durationStr, style: TextStyle(
          fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
        )),
      ]),
    ]);
  }

  Widget _buildControls(AppColors colors) {
    final spotify = colors.accentSpotify;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
            icon: Icons.skip_previous, onTap: _skipPrevious, colors: colors),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: spotify,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: spotify.withValues(alpha: 0.3),
                blurRadius: 16,
              )],
            ),
            child: Icon(
              _track.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.black, size: 26,
            ),
          ),
        ),
        const SizedBox(width: 20),
        _ControlButton(
            icon: Icons.skip_next, onTap: _skipNext, colors: colors),
      ],
    );
  }
  
  Widget _buildMatrixPreview(AppColors colors) {
    final spotify  = colors.accentSpotify;
    final progress = _track.durationMs > 0
        ? _simulatedProgress / _track.durationMs
        : 0.0;

    final ledLayout = switch (_layout) {
      SpotifyLayout.artOnly       => SpotifyLedLayout.artOnly,
      SpotifyLayout.textOnly      => SpotifyLedLayout.textOnly,
      SpotifyLayout.artAndText    => SpotifyLedLayout.artAndText,
      SpotifyLayout.scrollingText => SpotifyLedLayout.scrollingText,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _SectionLabel('MATRIX PREVIEW', colors),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: spotify.withValues(alpha: 0.08),
              border: Border.all(color: spotify.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _layout.name.toUpperCase().replaceAll('_', ' + '),
              style: TextStyle(
                fontSize: 8, color: spotify,
                fontFamily: 'monospace', letterSpacing: 0.8,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // height: 140 → width = 280 (2:1 guaranteed)
        LedMatrixPreview(
          height: 140,
          label: '64 × 32  ·  SPOTIFY MODE',
          content: SpotifyLedContent(
            title: _track.title,
            artist: _track.artist,
            showArtist: _showArtist,
            trackProgress: progress,
            showProgress: _showProgress,
            layout: ledLayout,
            spotifyColor: spotify,
          ),
        ),
      ],
    );
  }
 
  // ── Right panel ───────────────────────────────────────────────

  Widget _buildRightPanel(AppColors colors) {
    final spotify = colors.accentSpotify;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('DISPLAY LAYOUT', colors),
            const SizedBox(height: 10),
            _buildLayoutSelector(colors),
            const SizedBox(height: 20),
            if (_layout == SpotifyLayout.scrollingText) ...[
              _SectionLabel('SCROLL SPEED', colors),
              const SizedBox(height: 10),
              _buildScrollSpeedSelector(colors),
              const SizedBox(height: 20),
            ],
            _SectionLabel('BRIGHTNESS', colors),
            const SizedBox(height: 8),
            _buildBrightnessSlider(colors),
            const SizedBox(height: 20),
            _SectionLabel('OPTIONS', colors),
            const SizedBox(height: 10),
            _buildToggle('SHOW ARTIST',   _showArtist,   colors,
                (v) => setState(() => _showArtist = v)),
            const SizedBox(height: 8),
            _buildToggle('SHOW PROGRESS', _showProgress, colors,
                (v) => setState(() => _showProgress = v)),
            const SizedBox(height: 24),
            _ActionButton(
              label: _sendingToDevice ? 'LIVE ●' : 'SEND TO DEVICE',
              color: _sendingToDevice ? spotify : colors.accentBlue,
              onTap: _toggleSpotifyMode,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'REFRESH TRACK',
              color: spotify,
              onTap: () => setState(() => _simulatedProgress = 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutSelector(AppColors colors) {
    final spotify = colors.accentSpotify;
    const layouts = [
      (SpotifyLayout.artAndText,    'ART + TEXT',     'Album art with scrolling title'),
      (SpotifyLayout.artOnly,       'ART ONLY',       'Full matrix album art'),
      (SpotifyLayout.textOnly,      'TEXT ONLY',      'Static title and artist'),
      (SpotifyLayout.scrollingText, 'SCROLLING TEXT', 'Marquee style text'),
    ];
    return Column(
      children: layouts.map((l) {
        final active = _layout == l.$1;
        return GestureDetector(
          onTap: () => setState(() => _layout = l.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? spotify.withValues(alpha: 0.08) : Colors.transparent,
              border: Border.all(color: active ? spotify : colors.border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? spotify : colors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.$2, style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold,
                      color: active ? spotify : colors.textSecondary,
                      letterSpacing: 1, fontFamily: 'monospace',
                    )),
                    Text(l.$3, style: TextStyle(
                      fontSize: 9, color: colors.textMuted,
                      fontFamily: 'monospace',
                    )),
                  ],
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScrollSpeedSelector(AppColors colors) {
    final spotify = colors.accentSpotify;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: ScrollSpeed.values.map((s) {
          final active = _scrollSpeed == s;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _scrollSpeed = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? spotify.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(s.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.bold,
                    color: active ? spotify : colors.textMuted,
                    letterSpacing: 1, fontFamily: 'monospace',
                  )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBrightnessSlider(AppColors colors) {
    final spotify = colors.accentSpotify;
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor:   spotify,
          inactiveTrackColor: colors.border,
          thumbColor:         spotify,
          overlayColor:       spotify.withValues(alpha: 0.12),
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: _brightness,
          min: 0.1,
          max: 1.0,
          onChanged: (v) => setState(() => _brightness = v),
        ),
      ),
      Text('${(_brightness * 100).round()}%', style: TextStyle(
        fontSize: 10, color: colors.textMuted, fontFamily: 'monospace',
      )),
    ]);
  }

  Widget _buildToggle(
    String label,
    bool value,
    AppColors colors,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32, height: 18,
          decoration: BoxDecoration(
            color: value
                ? colors.toggleActive.withValues(alpha: 0.15)
                : colors.toggleInactive,
            border: Border.all(
              color: value ? colors.toggleActive : colors.border,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: value ? colors.toggleActive : colors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
          fontSize: 10, color: colors.textSecondary,
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ]),
    );
  }

  // ── Status bar ────────────────────────────────────────────────

  Widget _buildStatusBar(AppColors colors) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('LAYOUT', _layout.name.toUpperCase(),
            colors.accentSpotify, colors),
        const SizedBox(width: 24),
        _StatusItem('BRIGHTNESS', '${(_brightness * 100).round()}%',
            colors.textSecondary, colors),
        const Spacer(),
        Flexible(
          child: Text(
            '${_track.title} · ${_track.artist}',
            style: TextStyle(fontSize: 9, color: colors.textMuted,
              fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TrackTextDisplay extends StatelessWidget {
  final SpotifyTrack track;
  final bool showArtist;
  final Color spotifyColor;
  const _TrackTextDisplay({
    required this.track,
    required this.showArtist,
    required this.spotifyColor,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(track.title, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold,
        color: spotifyColor, fontFamily: 'monospace',
      ), maxLines: 1, overflow: TextOverflow.clip),
      if (showArtist)
        Text(track.artist, style: TextStyle(
          fontSize: 9,
          color: spotifyColor.withValues(alpha: 0.6),
          fontFamily: 'monospace',
        ), maxLines: 1, overflow: TextOverflow.clip),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final AppColors colors;
  const _ControlButton(
      {required this.icon, required this.onTap, required this.colors});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, color: colors.textSecondary, size: 20),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppColors colors;
  const _SectionLabel(this.text, this.colors);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(
    fontSize: 9, letterSpacing: 2, color: colors.textMuted,
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, textAlign: TextAlign.center, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold, color: color,
        letterSpacing: 1.5, fontFamily: 'monospace',
      )),
    ),
  );
}

class _StatusItem extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final AppColors colors;
  const _StatusItem(this.label, this.value, this.valueColor, this.colors);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: TextStyle(
      fontSize: 10, color: colors.textMuted, fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor, fontFamily: 'monospace',
    )),
  ]);
}