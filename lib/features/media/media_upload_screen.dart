import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../frame_encoder/frame_model.dart';
import '../frame_encoder/image_processor.dart';
import '../frame_encoder/rgb565_encoder.dart';
import '../../core/app_theme.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_uuids.dart';
import '../ui/connection_status.dart';
import '../ui/led_matrix_preview.dart';
import '../ui/theme_switcher.dart';

enum ResizeMode { stretch, letterbox, crop }

// ── Speed presets for the GIF duration adjuster ───────────────────────────────
// Each entry is (label, multiplier).
// multiplier < 1 = faster, multiplier > 1 = slower.
// "CUSTOM" activates a free slider for a per-frame ms override.
const List<(String, double)> kSpeedPresets = [
  ('0.25×', 0.25),
  ('0.5×',  0.50),
  ('1×',    1.00),
  ('2×',    2.00),
  ('4×',    4.00),
];

class MediaUploadScreen extends ConsumerStatefulWidget {
  const MediaUploadScreen({super.key});

  @override
  ConsumerState<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends ConsumerState<MediaUploadScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _rawBytes;
  String? _fileName;
  bool _isGif = false;
  FrameSequence? _sequence;
  bool _processing = false;
  bool _isSending = false;
  double _transferProgress = 0.0;
  String? _error;

  // ── Encode settings ────────────────────────────────────────────────────────
  ResizeMode _resizeMode = ResizeMode.letterbox;
  double _brightness = 1.0;
  bool _dithering = true;

  /// Grayscale — applies to both still images and GIFs.
  bool _grayscale = false;

  // ── GIF duration settings ──────────────────────────────────────────────────
  /// Index into kSpeedPresets, or -1 when "CUSTOM" free-slider is active.
  int _speedPresetIndex = 2; // default = 1× (unchanged)

  /// Whether the user has enabled free per-frame ms override (CUSTOM mode).
  bool _customDuration = false;

  /// The custom per-frame duration in ms (used when _customDuration == true).
  double _customFrameMs = 100.0; // 100 ms / frame ≈ 10 fps

  // ── Preview animation ──────────────────────────────────────────────────────
  int _previewFrame = 0;
  late final AnimationController _gifController;

  @override
  void initState() {
    super.initState();
    _gifController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_advanceGifFrame);
  }

  @override
  void dispose() {
    _gifController.dispose();
    super.dispose();
  }

  void _advanceGifFrame() {
    if (_sequence == null || !_sequence!.isAnimated) return;
    final totalMs = _sequence!.totalDurationMs;
    if (totalMs == 0) return;
    final elapsed = (_gifController.value * totalMs).round();
    int acc = 0;
    for (int i = 0; i < _sequence!.frameCount; i++) {
      acc += _sequence!.frames[i].durationMs;
      if (elapsed < acc) {
        if (_previewFrame != i) setState(() => _previewFrame = i);
        break;
      }
    }
  }

  // ── File picking ───────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() {
      _rawBytes = bytes;
      _fileName = file.name;
      _isGif = file.extension?.toLowerCase() == 'gif';
      _sequence = null;
      _error = null;
      _previewFrame = 0;
    });

    await _processImage();
  }

  // ── Compute GIF duration parameters for the encoder ───────────────────────

  (int? override, double multiplier) get _gifDurationParams {
    if (!_isGif) return (null, 1.0);
    if (_customDuration) return (_customFrameMs.round(), 1.0);
    return (null, kSpeedPresets[_speedPresetIndex].$2);
  }

  /// Total duration in ms after applying the current speed settings.
  /// Returns null if no sequence loaded.
  int? get _adjustedTotalMs {
    if (_sequence == null || !_sequence!.isAnimated) return null;
    return _sequence!.totalDurationMs;
    // Note: totalDurationMs already reflects the encode-time adjustment
    // because we re-encode on every settings change.
  }

  // ── Image processing ───────────────────────────────────────────────────────

  Future<void> _processImage() async {
    if (_rawBytes == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final processor = ImageProcessor(
        dithering: _dithering,
        brightness: _brightness,
        grayscale: _grayscale,
      );

      final (durationOverride, multiplier) = _gifDurationParams;

      FrameSequence sequence;
      if (_isGif) {
        sequence = await processor.processGif(
          _rawBytes!,
          frameDurationOverride: durationOverride,
          frameDurationMultiplier: multiplier,
        );
      } else {
        switch (_resizeMode) {
          case ResizeMode.letterbox:
            sequence = await processor.processLetterboxed(_rawBytes!);
          case ResizeMode.crop:
            sequence = await processor.processCropped(_rawBytes!);
          case ResizeMode.stretch:
            sequence = await processor.processBytes(_rawBytes!);
        }
      }

      setState(() {
        _sequence = sequence;
        _processing = false;
      });

      if (sequence.isAnimated && sequence.totalDurationMs > 0) {
        _gifController.duration =
            Duration(milliseconds: sequence.totalDurationMs);
        _gifController.repeat();
      } else {
        _gifController.stop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _processing = false;
      });
    }
  }

  // ── Send to device ─────────────────────────────────────────────────────────

  Future<void> _sendToDevice() async {
    if (_sequence == null) return;
    final bleService = ref.read(bleServiceProvider);
    final bleManager = ref.read(bleManagerProvider);

    if (bleManager.state != FrameonConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No device connected. Tap the status bar to connect.',
            style: TextStyle(fontFamily: 'monospace')),
      ));
      return;
    }

    setState(() {
      _isSending = true;
      _transferProgress = 0;
    });

    final sub = bleService.progressStream.listen((p) {
      if (mounted) setState(() => _transferProgress = p.progress);
    });

    try {
      await bleService.setMode(
          _sequence!.isAnimated ? kModeGif : kModePixelArt);
      await bleService.sendSequence(_sequence!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Sent to device',
              style: TextStyle(fontFamily: 'monospace')),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'monospace')),
        ));
      }
    } finally {
      await sub.cancel();
      if (mounted)
        setState(() {
          _isSending = false;
          _transferProgress = 0;
        });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bleManager = ref.watch(bleManagerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(children: [
        _buildHeader(colors),
        ConnectionStatusBar(
          manager: bleManager,
          onTap: () => DeviceScannerSheet.show(context, bleManager),
        ),
        if (_isSending)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TransferProgressBar(
              progress: _transferProgress,
              label: 'TRANSMITTING FRAME DATA',
              color: colors.accentBlue,
            ),
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

  // ── Header ─────────────────────────────────────────────────────────────────

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
        Text('MEDIA UPLOAD', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: colors.textPrimary, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        Text('GIF · PNG · JPG', style: TextStyle(
          fontSize: 11, color: colors.textMuted,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        if (_grayscale)
          _HeaderBadge(label: 'GRAYSCALE', color: colors.textSecondary),
        const SizedBox(width: 6),
        if (_sequence != null)
          _HeaderBadge(
            label: _sequence!.isAnimated
                ? '${_sequence!.frameCount} FRAMES'
                : 'STILL',
            color: _sequence!.isAnimated
                ? colors.accentYellow
                : colors.accent,
          ),
        const SizedBox(width: 8),
        const ThemeToggleButton(),
      ]),
    );
  }

  // ── Main panel ─────────────────────────────────────────────────────────────

  Widget _buildMainPanel(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Expanded(child: _buildDropZone(colors)),
        const SizedBox(height: 24),
        _buildMatrixPreview(colors),
      ]),
    );
  }

  Widget _buildDropZone(AppColors colors) {
    if (_rawBytes != null && !_processing) return _buildImagePreview(colors);

    return GestureDetector(
      onTap: _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(8),
          color: colors.accent.withValues(alpha: 0.02),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_processing) ...[
              SizedBox(
                width: 32, height: 32,
                child: CircularProgressIndicator(
                    color: colors.accent, strokeWidth: 1.5),
              ),
              const SizedBox(height: 16),
              Text('ENCODING...', style: TextStyle(
                fontSize: 11, color: colors.accent,
                letterSpacing: 2, fontFamily: 'monospace',
              )),
            ] else if (_error != null) ...[
              Icon(Icons.error_outline, color: colors.accentRed, size: 32),
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(
                fontSize: 10, color: colors.accentRed, fontFamily: 'monospace',
              ), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _SmallButton(label: 'TRY AGAIN', onTap: _pickFile, colors: colors),
            ] else ...[
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.upload_outlined,
                    color: colors.textMuted, size: 28),
              ),
              const SizedBox(height: 20),
              Text('TAP TO UPLOAD', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: colors.accent, letterSpacing: 2, fontFamily: 'monospace',
              )),
              const SizedBox(height: 8),
              Text('PNG · JPG · GIF · BMP · WebP', style: TextStyle(
                fontSize: 10, color: colors.textMuted,
                letterSpacing: 1, fontFamily: 'monospace',
              )),
              const SizedBox(height: 4),
              Text('Encoded to 64 × 32 RGB565', style: TextStyle(
                fontSize: 10, color: colors.textMuted,
                letterSpacing: 0.5, fontFamily: 'monospace',
              )),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildImagePreview(AppColors colors) {
    return Stack(children: [
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          color: colors.inputBg,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: _grayscale
              ? ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0,      0,      0,      1, 0,
                  ]),
                  child: Image.memory(_rawBytes!, fit: BoxFit.contain),
                )
              : Image.memory(_rawBytes!, fit: BoxFit.contain),
        ),
      ),
      Positioned(
        top: 12, right: 12,
        child: GestureDetector(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('CHANGE', style: TextStyle(
              fontSize: 9, color: colors.textSecondary,
              letterSpacing: 1, fontFamily: 'monospace',
            )),
          ),
        ),
      ),
      if (_fileName != null)
        Positioned(
          bottom: 12, left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_fileName!, style: TextStyle(
              fontSize: 9, color: colors.textSecondary,
              letterSpacing: 0.5, fontFamily: 'monospace',
            )),
          ),
        ),
    ]);
  }

  Widget _buildMatrixPreview(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _SectionLabel('MATRIX PREVIEW', colors),
          const Spacer(),
          if (_sequence != null && _sequence!.isAnimated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.accentYellow.withValues(alpha: 0.1),
                border: Border.all(
                    color: colors.accentYellow.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'FRAME ${_previewFrame + 1} / ${_sequence!.frameCount}',
                style: TextStyle(
                  fontSize: 8, color: colors.accentYellow,
                  fontFamily: 'monospace', letterSpacing: 0.8,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        LedMatrixPreview(
          height: 160,
          label: '64 × 32  ·  RGB565'
              '${_grayscale ? "  ·  GRAYSCALE" : ""}',
          content: _sequence != null
              ? Rgb565LedContent(
                  bytes: _sequence!.frames[_previewFrame].bytes)
              : EmptyLedContent(color: colors.accent),
        ),
      ],
    );
  }

  // ── Right panel ────────────────────────────────────────────────────────────

  Widget _buildRightPanel(AppColors colors) {
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
            // ── Resize mode (hidden for GIFs — resize mode doesn't apply) ──
            if (!_isGif) ...[
              _SectionLabel('RESIZE MODE', colors),
              const SizedBox(height: 10),
              ..._buildResizeModes(colors),
              const SizedBox(height: 20),
            ],

            // ── Brightness ──────────────────────────────────────────────────
            _SectionLabel('BRIGHTNESS', colors),
            const SizedBox(height: 8),
            _buildBrightnessSlider(colors),
            const SizedBox(height: 20),

            // ── Options (dithering + grayscale) ─────────────────────────────
            _SectionLabel('OPTIONS', colors),
            const SizedBox(height: 10),
            _buildToggle(
              'DITHERING', _dithering, colors.toggleActive, colors,
              (v) {
                setState(() => _dithering = v);
                if (_rawBytes != null) _processImage();
              },
            ),
            const SizedBox(height: 8),
            _buildToggle(
              'GRAYSCALE', _grayscale, colors.textSecondary, colors,
              (v) {
                setState(() => _grayscale = v);
                if (_rawBytes != null) _processImage();
              },
            ),
            const SizedBox(height: 20),

            // ── GIF duration (only shown for animated GIFs) ─────────────────
            if (_isGif && _sequence != null && _sequence!.isAnimated) ...[
              _SectionLabel('GIF SPEED', colors),
              const SizedBox(height: 10),
              _buildGifDurationSection(colors),
              const SizedBox(height: 20),
            ],

            // ── Output info ─────────────────────────────────────────────────
            if (_sequence != null) ...[
              _SectionLabel('OUTPUT', colors),
              const SizedBox(height: 8),
              _InfoRow('Frames', '${_sequence!.frameCount}', colors),
              _InfoRow('Bytes',
                '${_sequence!.frames.first.byteCount * _sequence!.frameCount}',
                colors),
              if (_sequence!.isAnimated)
                _InfoRow('Duration', '${_sequence!.totalDurationMs}ms', colors),
              if (_sequence!.isAnimated && _sequence!.frameCount > 0)
                _InfoRow('Per frame',
                  '${(_sequence!.totalDurationMs / _sequence!.frameCount).round()}ms',
                  colors),
              const SizedBox(height: 20),
            ],

            // ── Actions ──────────────────────────────────────────────────────
            _ActionButton(
              label: _isSending ? 'SENDING...' : 'SEND TO DEVICE',
              color: colors.accentBlue,
              enabled: _sequence != null && !_isSending,
              onTap: _sendToDevice,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'RE-ENCODE',
              color: colors.accent,
              enabled: _rawBytes != null,
              onTap: _processImage,
            ),
          ],
        ),
      ),
    );
  }

  // ── GIF duration section ───────────────────────────────────────────────────

  Widget _buildGifDurationSection(AppColors colors) {
    final accent = colors.accentYellow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Speed preset chips ────────────────────────────────────────────
        Row(
          children: List.generate(kSpeedPresets.length, (i) {
            final active = !_customDuration && _speedPresetIndex == i;
            final label = kSpeedPresets[i].$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < kSpeedPresets.length - 1 ? 4 : 0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _customDuration = false;
                      _speedPresetIndex = i;
                    });
                    _processImage();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      border: Border.all(
                          color: active ? accent : colors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(label, textAlign: TextAlign.center, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.bold,
                      color: active ? accent : colors.textMuted,
                      fontFamily: 'monospace',
                    )),
                  ),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 10),

        // ── Custom toggle ─────────────────────────────────────────────────
        GestureDetector(
          onTap: () {
            setState(() => _customDuration = !_customDuration);
            _processImage();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _customDuration
                  ? accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                  color: _customDuration ? accent : colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              Icon(Icons.tune,
                  size: 12,
                  color: _customDuration ? accent : colors.textMuted),
              const SizedBox(width: 6),
              Text('CUSTOM', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold,
                color: _customDuration ? accent : colors.textMuted,
                letterSpacing: 1, fontFamily: 'monospace',
              )),
              const Spacer(),
              if (_customDuration)
                Text('${_customFrameMs.round()} ms/frame', style: TextStyle(
                  fontSize: 9,
                  color: accent,
                  fontFamily: 'monospace',
                )),
            ]),
          ),
        ),

        // ── Custom slider (visible only in custom mode) ───────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _customDuration
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: colors.border,
                  thumbColor: accent,
                  overlayColor: accent.withValues(alpha: 0.12),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: _customFrameMs,
                  min: 16,
                  max: 500,
                  divisions: 97, // 16–500 in ~5ms steps
                  onChanged: (v) => setState(() => _customFrameMs = v),
                  onChangeEnd: (_) => _processImage(),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('16ms (fast)', style: TextStyle(
                    fontSize: 8, color: colors.textMuted,
                    fontFamily: 'monospace',
                  )),
                  Text('500ms (slow)', style: TextStyle(
                    fontSize: 8, color: colors.textMuted,
                    fontFamily: 'monospace',
                  )),
                ],
              ),
            ]),
          ),
        ),

        const SizedBox(height: 8),

        // ── Effective FPS display ─────────────────────────────────────────
        if (_sequence != null && _sequence!.isAnimated &&
            _sequence!.frameCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.inputBg,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('EFFECTIVE', style: TextStyle(
                  fontSize: 8, color: colors.textMuted,
                  fontFamily: 'monospace', letterSpacing: 1,
                )),
                Text(
                  _effectiveFpsString,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: accent, fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String get _effectiveFpsString {
    if (_sequence == null || !_sequence!.isAnimated) return '—';
    final avgMs =
        _sequence!.totalDurationMs / _sequence!.frameCount;
    final fps = 1000 / avgMs;
    return '${fps.toStringAsFixed(1)} fps  ·  ${avgMs.round()} ms/f';
  }

  // ── Resize mode options ────────────────────────────────────────────────────

  List<Widget> _buildResizeModes(AppColors colors) {
    const modes = [
      (ResizeMode.letterbox, 'LETTERBOX', 'Preserve ratio, black bars'),
      (ResizeMode.crop,      'CROP',      'Fill matrix, centre crop'),
      (ResizeMode.stretch,   'STRETCH',   'Fill matrix, may distort'),
    ];
    return modes.map((m) {
      final active = _resizeMode == m.$1;
      return GestureDetector(
        onTap: () {
          setState(() => _resizeMode = m.$1);
          if (_rawBytes != null) _processImage();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? colors.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(color: active ? colors.accent : colors.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? colors.accent : colors.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.$2, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                color: active ? colors.accent : colors.textSecondary,
                letterSpacing: 1, fontFamily: 'monospace',
              )),
              Text(m.$3, style: TextStyle(
                fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
              )),
            ]),
          ]),
        ),
      );
    }).toList();
  }

  // ── Sliders / toggles ──────────────────────────────────────────────────────

  Widget _buildBrightnessSlider(AppColors colors) {
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: colors.accent,
          inactiveTrackColor: colors.border,
          thumbColor: colors.accent,
          overlayColor: colors.accent.withValues(alpha: 0.12),
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: _brightness,
          min: 0.1,
          max: 1.0,
          onChanged: (v) => setState(() => _brightness = v),
          onChangeEnd: (_) {
            if (_rawBytes != null) _processImage();
          },
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
    Color activeColor,
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
                ? activeColor.withValues(alpha: 0.15)
                : colors.toggleInactive,
            border: Border.all(
                color: value ? activeColor : colors.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: value ? activeColor : colors.textMuted,
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

  // ── Status bar ─────────────────────────────────────────────────────────────

  Widget _buildStatusBar(AppColors colors) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        if (!_isGif)
          _StatusItem('MODE', _resizeMode.name.toUpperCase(),
              colors.accent, colors),
        if (!_isGif) const SizedBox(width: 24),
        _StatusItem('BRIGHTNESS', '${(_brightness * 100).round()}%',
            colors.textSecondary, colors),
        const SizedBox(width: 24),
        _StatusItem('DITHER', _dithering ? 'ON' : 'OFF',
            _dithering ? colors.accent : colors.textMuted, colors),
        const SizedBox(width: 24),
        _StatusItem('GRAY', _grayscale ? 'ON' : 'OFF',
            _grayscale ? colors.textSecondary : colors.textMuted, colors),
        const Spacer(),
        if (_sequence != null)
          Text(
            _sequence!.isAnimated
                ? 'GIF · ${_sequence!.frameCount} frames · ${_sequence!.totalDurationMs}ms · ${_effectiveFpsString}'
                : 'STILL · ${_sequence!.frames.first.byteCount} bytes',
            style: TextStyle(fontSize: 9, color: colors.textMuted,
                fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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

class _InfoRow extends StatelessWidget {
  final String label, value;
  final AppColors colors;
  const _InfoRow(this.label, this.value, this.colors);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
            fontSize: 10, color: colors.textMuted, fontFamily: 'monospace')),
        Text(value, style: TextStyle(
            fontSize: 10, color: colors.textSecondary,
            fontFamily: 'monospace')),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label, required this.color,
    required this.onTap, this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Opacity(
      opacity: enabled ? 1.0 : 0.3,
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
    ),
  );
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final AppColors colors;
  const _SmallButton(
      {required this.label, required this.onTap, required this.colors});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10, color: colors.textSecondary, fontFamily: 'monospace',
      )),
    ),
  );
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _HeaderBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label, style: TextStyle(
      fontSize: 9, color: color, letterSpacing: 1.5, fontFamily: 'monospace',
    )),
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