import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_uuids.dart';
import '../ui/connection_status.dart';

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

  double get progress => durationMs > 0 ? progressMs / durationMs : 0;

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
enum ScrollSpeed { slow, medium, fast }

// ── Screen ────────────────────────────────────────────────────────────────────

class SpotifyScreen extends ConsumerStatefulWidget {
  const SpotifyScreen({super.key});

  @override
  ConsumerState<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends ConsumerState<SpotifyScreen>
    with SingleTickerProviderStateMixin {
  SpotifyTrack _track = _kMockTrack;
  bool _connected = false;
  bool _sendingToDevice = false;

  SpotifyLayout _layout = SpotifyLayout.artAndText;
  ScrollSpeed _scrollSpeed = ScrollSpeed.medium;
  bool _showProgress = true;
  bool _showArtist = true;
  double _brightness = 0.85;

  // Scrolling text animation
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

    // Simulate progress ticking
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_track.isPlaying && mounted) {
        setState(() {
          _simulatedProgress = (_simulatedProgress + 1000)
              .clamp(0, _track.durationMs);
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

  // Playback commands go to Spotify Web API (not BLE).
  // The ESP32 polls Spotify autonomously; these mirror state in the app UI.
  void _togglePlayPause() {
    setState(() => _track = SpotifyTrack(
      title: _track.title,
      artist: _track.artist,
      album: _track.album,
      durationMs: _track.durationMs,
      progressMs: _simulatedProgress,
      isPlaying: !_track.isPlaying,
    ));
    // Spotify API call wired in next sprint
  }

  void _skipNext() {
    // Spotify API call wired in next sprint
    setState(() => _simulatedProgress = 0);
  }

  void _skipPrevious() {
    // Spotify API call wired in next sprint
    setState(() => _simulatedProgress = 0);
  }

  Future<void> _toggleSpotifyMode() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (!_sendingToDevice) {
      if (bleManager.state != FrameonConnectionState.connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No device connected.',
              style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: Color(0xFF1A0A0A),
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
          backgroundColor: const Color(0xFF1A0A0A),
        ));
      }
    } else {
      setState(() => _sendingToDevice = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bleManager = ref.watch(bleManagerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Column(children: [
        _buildHeader(),
        ConnectionStatusBar(
          manager: bleManager,
          onTap: () => DeviceScannerSheet.show(context, bleManager),
        ),
        Expanded(
          child: Row(children: [
            Expanded(child: _buildMainPanel()),
            _buildRightPanel(),
          ]),
        ),
        _buildStatusBar(),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios, color: Color(0xFF444444), size: 16),
        ),
        const SizedBox(width: 16),
        const Text('SPOTIFY', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: Colors.white, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        const Text('NOW PLAYING', style: TextStyle(
          fontSize: 11, color: Color(0xFF444444),
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        _buildConnectButton(),
      ]),
    );
  }

  Widget _buildConnectButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _connected = !_connected);
        // TODO: trigger Spotify OAuth flow
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: _connected
              ? const Color(0xFF1DB95422)
              : Colors.transparent,
          border: Border.all(
            color: _connected ? const Color(0xFF1DB954) : const Color(0xFF333333),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_connected)
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF1DB954), shape: BoxShape.circle,
              ),
            ),
          Text(
            _connected ? 'CONNECTED' : 'CONNECT SPOTIFY',
            style: TextStyle(
              fontSize: 10,
              color: _connected ? const Color(0xFF1DB954) : const Color(0xFF555555),
              letterSpacing: 1, fontFamily: 'monospace',
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMainPanel() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Expanded(child: _buildNowPlayingCard()),
        const SizedBox(height: 20),
        _buildMatrixPreview(),
      ]),
    );
  }

  Widget _buildNowPlayingCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border.all(color: const Color(0xFF1A1A2E)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // Album art placeholder
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1A1A2E)),
            ),
            child: _track.albumArtUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(_track.albumArtUrl!, fit: BoxFit.cover),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note,
                            color: Color(0xFF1DB954), size: 48),
                        const SizedBox(height: 8),
                        Text(
                          _connected ? 'NO ALBUM ART' : 'NOT CONNECTED',
                          style: const TextStyle(fontSize: 10,
                            color: Color(0xFF333333), fontFamily: 'monospace',
                            letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Track info
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _track.title.toUpperCase(),
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold,
                color: Colors.white, letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${_track.artist} · ${_track.album}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF555555),
                fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // Progress bar
            _buildProgressBar(),
            const SizedBox(height: 16),

            // Controls
            _buildControls(),
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }

  Widget _buildProgressBar() {
    final progress = _track.durationMs > 0
        ? _simulatedProgress / _track.durationMs
        : 0.0;
    return Column(children: [
      Stack(children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Text(_track.formatDuration(_simulatedProgress), style: const TextStyle(
          fontSize: 9, color: Color(0xFF444444), fontFamily: 'monospace',
        )),
        const Spacer(),
        Text(_track.durationStr, style: const TextStyle(
          fontSize: 9, color: Color(0xFF444444), fontFamily: 'monospace',
        )),
      ]),
    ]);
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(icon: Icons.skip_previous, onTap: _skipPrevious),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: const Color(0xFF1DB954).withValues(alpha: 0.3),
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
        _ControlButton(icon: Icons.skip_next, onTap: _skipNext),
      ],
    );
  }

  Widget _buildMatrixPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          _SectionLabel('MATRIX PREVIEW'),
          SizedBox(width: 8),
          Text('64 × 32', style: TextStyle(
            fontSize: 9, color: Color(0xFF333333), fontFamily: 'monospace',
          )),
        ]),
        const SizedBox(height: 8),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: const Color(0xFF1A2A1A)),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(
              color: const Color(0xFF1DB954).withValues(alpha: 0.04),
              blurRadius: 20,
            )],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: _buildLayoutPreview(),
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutPreview() {
    switch (_layout) {
      case SpotifyLayout.artOnly:
        return Center(
          child: Container(
            width: 60, height: 60,
            color: const Color(0xFF1DB954).withValues(alpha: 0.3),
            child: const Icon(Icons.music_note,
                color: Color(0xFF1DB954), size: 30),
          ),
        );

      case SpotifyLayout.textOnly:
      case SpotifyLayout.scrollingText:
        final isScrolling = _layout == SpotifyLayout.scrollingText;
        return Center(
          child: isScrolling
              ? AnimatedBuilder(
                  animation: _scrollCtrl,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(-200 * _scrollCtrl.value + 100, 0),
                    child: _TrackTextDisplay(track: _track, showArtist: _showArtist),
                  ),
                )
              : _TrackTextDisplay(track: _track, showArtist: _showArtist),
        );

      case SpotifyLayout.artAndText:
        return Row(children: [
          Container(
            width: 72,
            color: const Color(0xFF1DB954).withValues(alpha: 0.15),
            child: const Center(child: Icon(Icons.music_note,
                color: Color(0xFF1DB954), size: 24)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _TrackTextDisplay(track: _track, showArtist: _showArtist),
            ),
          ),
        ]);
    }
  }

  // ── Right panel ───────────────────────────────────────────────

  Widget _buildRightPanel() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(left: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('DISPLAY LAYOUT'),
            const SizedBox(height: 10),
            _buildLayoutSelector(),
            const SizedBox(height: 20),
            if (_layout == SpotifyLayout.scrollingText) ...[
              const _SectionLabel('SCROLL SPEED'),
              const SizedBox(height: 10),
              _buildScrollSpeedSelector(),
              const SizedBox(height: 20),
            ],
            const _SectionLabel('BRIGHTNESS'),
            const SizedBox(height: 8),
            _buildBrightnessSlider(),
            const SizedBox(height: 20),
            const _SectionLabel('OPTIONS'),
            const SizedBox(height: 10),
            _buildToggle('SHOW ARTIST',   _showArtist,  (v) => setState(() => _showArtist = v)),
            const SizedBox(height: 8),
            _buildToggle('SHOW PROGRESS', _showProgress, (v) => setState(() => _showProgress = v)),
            const SizedBox(height: 24),
            _ActionButton(
              label: _sendingToDevice ? 'LIVE ●' : 'SEND TO DEVICE',
              color: _sendingToDevice ? const Color(0xFF1DB954) : const Color(0xFF00B4FF),
              onTap: _toggleSpotifyMode,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'REFRESH TRACK',
              color: const Color(0xFF1DB954),
              onTap: () {
                // Spotify API polling wired up in next sprint
                setState(() => _simulatedProgress = 0);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutSelector() {
    const layouts = [
      (SpotifyLayout.artAndText,     'ART + TEXT',      'Album art with scrolling title'),
      (SpotifyLayout.artOnly,        'ART ONLY',        'Full matrix album art'),
      (SpotifyLayout.textOnly,       'TEXT ONLY',       'Static title and artist'),
      (SpotifyLayout.scrollingText,  'SCROLLING TEXT',  'Marquee style text'),
    ];
    return Column(
      children: layouts.map((l) {
        final active = _layout == l.$1;
        return GestureDetector(
          onTap: () => setState(() => _layout = l.$1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF1DB95415) : Colors.transparent,
              border: Border.all(
                color: active ? const Color(0xFF1DB954) : const Color(0xFF222222),
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? const Color(0xFF1DB954) : const Color(0xFF333333),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.$2, style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: active ? const Color(0xFF1DB954) : const Color(0xFF555555),
                    letterSpacing: 1, fontFamily: 'monospace',
                  )),
                  Text(l.$3, style: const TextStyle(
                    fontSize: 9, color: Color(0xFF333333), fontFamily: 'monospace',
                  )),
                ]),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScrollSpeedSelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF222222)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: ScrollSpeed.values.map((s) {
          final active = _scrollSpeed == s;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _scrollSpeed = s),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF1DB95415) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(s.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.bold,
                    color: active ? const Color(0xFF1DB954) : const Color(0xFF444444),
                    letterSpacing: 1, fontFamily: 'monospace',
                  )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBrightnessSlider() {
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFF1DB954),
          inactiveTrackColor: const Color(0xFF1A1A2E),
          thumbColor: const Color(0xFF1DB954),
          overlayColor: const Color(0xFF1DB95422),
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
      Text('${(_brightness * 100).round()}%', style: const TextStyle(
        fontSize: 10, color: Color(0xFF444444), fontFamily: 'monospace',
      )),
    ]);
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(children: [
        Container(
          width: 32, height: 18,
          decoration: BoxDecoration(
            color: value ? const Color(0xFF1DB95422) : const Color(0xFF1A1A2E),
            border: Border.all(
              color: value ? const Color(0xFF1DB954) : const Color(0xFF333333),
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
                color: value ? const Color(0xFF1DB954) : const Color(0xFF333333),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(
          fontSize: 10, color: Color(0xFF555555),
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ]),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('LAYOUT', _layout.name.toUpperCase(), const Color(0xFF1DB954)),
        const SizedBox(width: 24),
        _StatusItem('BRIGHTNESS', '${(_brightness * 100).round()}%', const Color(0xFF666666)),
        const Spacer(),
        Text(
          '${_track.title} · ${_track.artist}',
          style: const TextStyle(fontSize: 9, color: Color(0xFF333333),
            fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TrackTextDisplay extends StatelessWidget {
  final SpotifyTrack track;
  final bool showArtist;
  const _TrackTextDisplay({required this.track, required this.showArtist});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(track.title, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold,
        color: Color(0xFF1DB954), fontFamily: 'monospace',
      ), maxLines: 1, overflow: TextOverflow.clip),
      if (showArtist)
        Text(track.artist, style: const TextStyle(
          fontSize: 9, color: Color(0xFF555555), fontFamily: 'monospace',
        ), maxLines: 1, overflow: TextOverflow.clip),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ControlButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF222222)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, color: const Color(0xFF666666), size: 20),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    fontSize: 9, letterSpacing: 2, color: Color(0xFF333333),
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.color, required this.onTap});
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
  const _StatusItem(this.label, this.value, this.valueColor);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: const TextStyle(
      fontSize: 10, color: Color(0xFF333333), fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor, fontFamily: 'monospace',
    )),
  ]);
}