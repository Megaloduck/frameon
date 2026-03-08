import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_uuids.dart';
import '../frame_encoder/frame_model.dart';
import '../ui/connection_status.dart';
import '../ui/led_matrix_preview.dart';
import '../ui/theme_switcher.dart';
import 'led_font_library.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kCols = 64;
const int _kRows = 32;

// ── Preset colors ─────────────────────────────────────────────────────────────

const List<Color> _kColors = [
  Color(0xFF00FF41), // green
  Color(0xFFFFFFFF), // white
  Color(0xFF00B4FF), // cyan
  Color(0xFFFFE600), // yellow
  Color(0xFFFF2D2D), // red
  Color(0xFFFF00CC), // pink
  Color(0xFFBF00FF), // purple
  Color(0xFFFF6600), // orange
];

// ── Text alignment enum ───────────────────────────────────────────────────────

enum BitmapAlign { left, center, right }

// ── Animation effects ─────────────────────────────────────────────────────────

enum TextEffect {
  none,
  scrollLeft,
  scrollRight,
  blink,
  pulse,
  glitch,
  slideIn,
  bounce,
}

extension TextEffectLabel on TextEffect {
  String get label => switch (this) {
        TextEffect.none       => 'STATIC',
        TextEffect.scrollLeft => 'SCROLL ←',
        TextEffect.scrollRight=> 'SCROLL →',
        TextEffect.blink      => 'BLINK',
        TextEffect.pulse      => 'PULSE',
        TextEffect.glitch     => 'GLITCH',
        TextEffect.slideIn    => 'SLIDE IN',
        TextEffect.bounce     => 'BOUNCE',
      };

  String get description => switch (this) {
        TextEffect.none        => 'No animation — display is frozen.',
        TextEffect.scrollLeft  => 'Text scrolls continuously from right to left.',
        TextEffect.scrollRight => 'Text scrolls continuously from left to right.',
        TextEffect.blink       => 'All rows flash on and off.',
        TextEffect.pulse       => 'Brightness fades in and out smoothly.',
        TextEffect.glitch      => 'Random pixel noise bursts between frames.',
        TextEffect.slideIn     => 'Text slides in from the right and stops center.',
        TextEffect.bounce      => 'Text bounces left and right.',
      };

  /// Approximate frames-per-second for this effect.
  int get fps => switch (this) {
        TextEffect.none        => 0,
        TextEffect.scrollLeft  => 24,
        TextEffect.scrollRight => 24,
        TextEffect.blink       => 4,
        TextEffect.pulse       => 30,
        TextEffect.glitch      => 20,
        TextEffect.slideIn     => 30,
        TextEffect.bounce      => 30,
      };
}

// ── Per-row configuration ─────────────────────────────────────────────────────

class _RowConfig {
  String text;
  Color color;
  bool enabled;
  BitmapAlign align;

  _RowConfig({
    this.text = '',
    this.color = const Color(0xFF00FF41),
    this.enabled = true,
    this.align = BitmapAlign.center,
  });

  _RowConfig copyWith({
    String? text,
    Color? color,
    bool? enabled,
    BitmapAlign? align,
  }) => _RowConfig(
    text: text ?? this.text,
    color: color ?? this.color,
    enabled: enabled ?? this.enabled,
    align: align ?? this.align,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class FontTextScreen extends ConsumerStatefulWidget {
  const FontTextScreen({super.key});

  @override
  ConsumerState<FontTextScreen> createState() => _FontTextScreenState();
}

class _FontTextScreenState extends ConsumerState<FontTextScreen>
    with SingleTickerProviderStateMixin {
  // ── Font selection ─────────────────────────────────────────────
  LedFontId _fontId = LedFontId.matrixtype;
  LedFont get _font => LedFontLibrary.get(_fontId);

  // ── Row configs ────────────────────────────────────────────────
  late List<_RowConfig> _rows;
  late List<TextEditingController> _controllers;

  // ── Selected row for editing ───────────────────────────────────
  int _selectedRow = 0;

  // ── Effect ────────────────────────────────────────────────────
  TextEffect _effect = TextEffect.none;

  // ── Scroll speed (pixels per frame) ───────────────────────────
  int _scrollSpeed = 1; // 1..4

  // ── Animation state ───────────────────────────────────────────
  late AnimationController _animController;

  /// Continuous tick counter — drives all effects.
  int _tick = 0;

  // ── Transfer ───────────────────────────────────────────────────
  bool _isSending = false;
  double _transferProgress = 0;

  // ── Glitch RNG ────────────────────────────────────────────────
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _rows = List.generate(4, (i) => _RowConfig(
      text: i == 0 ? 'HELLO' : '',
      color: _kColors[i % _kColors.length],
      enabled: i == 0,
    ));
    _controllers = List.generate(4, (i) =>
        TextEditingController(text: _rows[i].text));
    for (int i = 0; i < 4; i++) {
      final idx = i;
      _controllers[idx].addListener(() {
        setState(() => _rows[idx] = _rows[idx].copyWith(
            text: _controllers[idx].text));
      });
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )..addListener(_onAnimTick);
  }

  void _startOrStopAnimation() {
    if (_effect == TextEffect.none) {
      _animController.stop();
      _tick = 0;
    } else {
      if (!_animController.isAnimating) {
        _animController.forward();
      }
    }
  }

  void _onAnimTick() {
    // Throttle by fps
    final fps = _effect.fps;
    if (fps <= 0) return;
    if (mounted) setState(() => _tick++);
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  // ── Render helpers ─────────────────────────────────────────────

  /// Render a single base frame (no animation offset) to a flat RGB565 list.
  List<int> _renderBase({int? scrollOffsetX, double? brightnessMul}) {
    final font   = _font;
    final pixels = List<int>.filled(_kCols * _kRows * 2, 0);

    for (int slot = 0; slot < font.maxLines && slot < 4; slot++) {
      final cfg = _rows[slot];
      if (!cfg.enabled || cfg.text.isEmpty) continue;

      final color = cfg.color;
      final r5 = (color.red   >> 3) & 0x1F;
      final g6 = (color.green >> 2) & 0x3F;
      final b5 = (color.blue  >> 3) & 0x1F;

      // Apply brightness multiplier for pulse effect
      final mul = brightnessMul ?? 1.0;
      final r5m = ((r5 * mul).round()).clamp(0, 0x1F);
      final g6m = ((g6 * mul).round()).clamp(0, 0x3F);
      final b5m = ((b5 * mul).round()).clamp(0, 0x1F);

      final word = (r5m << 11) | (g6m << 5) | b5m;
      final hi = (word >> 8) & 0xFF;
      final lo = word & 0xFF;

      final rowY  = font.rowY[slot];
      final textW = font.textWidth(cfg.text);

      int startX;
      if (scrollOffsetX != null) {
        startX = scrollOffsetX;
      } else {
        switch (cfg.align) {
          case BitmapAlign.left:   startX = 0;
          case BitmapAlign.center: startX = font.centeredX(cfg.text);
          case BitmapAlign.right:  startX = (_kCols - textW).clamp(0, _kCols - 1);
        }
      }

      int penX = startX;
      for (int ci = 0; ci < cfg.text.length; ci++) {
        final glyph = font.glyphFor(cfg.text[ci]);
        for (int gr = 0; gr < font.charHeight; gr++) {
          final mask    = glyph.rows[gr];
          final screenY = rowY + gr;
          if (screenY < 0 || screenY >= _kRows) continue;
          for (int gc = 0; gc < glyph.width; gc++) {
            final bit = (mask >> (glyph.width - 1 - gc)) & 1;
            if (bit == 0) continue;
            final screenX = penX + gc;
            if (screenX < 0 || screenX >= _kCols) continue;
            final pixelIdx = (screenY * _kCols + screenX) * 2;
            pixels[pixelIdx]     = hi;
            pixels[pixelIdx + 1] = lo;
          }
        }
        penX += glyph.width + font.charGap;
      }
    }
    return pixels;
  }

  /// Compute the widest active row text width across all rows.
  int _maxTextWidth() {
    int w = 0;
    for (int i = 0; i < _font.maxLines && i < 4; i++) {
      if (_rows[i].enabled && _rows[i].text.isNotEmpty) {
        w = math.max(w, _font.textWidth(_rows[i].text));
      }
    }
    return w;
  }

  // ── Animated render ────────────────────────────────────────────

  List<int> _renderAnimated() {
    final fps  = _effect.fps > 0 ? _effect.fps : 1;
    final frame = _tick; // raw tick — throttled above

    switch (_effect) {
      // ── Static ──────────────────────────────────────────────────
      case TextEffect.none:
        return _renderBase();

      // ── Scroll left ─────────────────────────────────────────────
      case TextEffect.scrollLeft: {
        final totalW = _maxTextWidth() + _kCols; // full cycle width
        if (totalW == 0) return _renderBase();
        final speed  = _scrollSpeed;
        final offset = _kCols - ((frame * speed) % (totalW));
        return _renderBase(scrollOffsetX: offset);
      }

      // ── Scroll right ────────────────────────────────────────────
      case TextEffect.scrollRight: {
        final maxW   = _maxTextWidth();
        if (maxW == 0) return _renderBase();
        final totalW = maxW + _kCols;
        final speed  = _scrollSpeed;
        final offset = -maxW + ((frame * speed) % totalW);
        return _renderBase(scrollOffsetX: offset);
      }

      // ── Blink ───────────────────────────────────────────────────
      case TextEffect.blink: {
        final on = (frame ~/ 2).isEven; // 2 ticks on / 2 ticks off
        return on ? _renderBase() : List<int>.filled(_kCols * _kRows * 2, 0);
      }

      // ── Pulse ───────────────────────────────────────────────────
      case TextEffect.pulse: {
        final t = (frame % fps) / fps;
        final brightness = (math.sin(t * 2 * math.pi) * 0.5 + 0.5);
        return _renderBase(brightnessMul: brightness);
      }

      // ── Glitch ──────────────────────────────────────────────────
      case TextEffect.glitch: {
        final pixels = _renderBase();
        // Every ~4 frames add noise bursts
        if (frame % 3 == 0) {
          final bursts = 3 + _rng.nextInt(6);
          for (int b = 0; b < bursts; b++) {
            final rx  = _rng.nextInt(_kCols);
            final ry  = _rng.nextInt(_kRows);
            final rw  = 2 + _rng.nextInt(10);
            final col = _kColors[_rng.nextInt(_kColors.length)];
            final r5  = (col.red   >> 3) & 0x1F;
            final g6  = (col.green >> 2) & 0x3F;
            final b5  = (col.blue  >> 3) & 0x1F;
            final hi  = ((r5 << 3) | (g6 >> 3)) & 0xFF;
            final lo  = ((g6 & 0x07) << 5) | b5;
            for (int x = rx; x < math.min(rx + rw, _kCols); x++) {
              final idx = (ry * _kCols + x) * 2;
              pixels[idx]     = hi;
              pixels[idx + 1] = lo;
            }
            // Horizontal shift on a random row
            final shiftRow = _rng.nextInt(_kRows);
            final shift    = _rng.nextInt(8) - 4;
            if (shift != 0) {
              final rowStart = shiftRow * _kCols * 2;
              final tmp = List<int>.from(
                  pixels.sublist(rowStart, rowStart + _kCols * 2));
              for (int x = 0; x < _kCols; x++) {
                final sx = (x + shift).clamp(0, _kCols - 1);
                pixels[rowStart + x * 2]     = tmp[sx * 2];
                pixels[rowStart + x * 2 + 1] = tmp[sx * 2 + 1];
              }
            }
          }
        }
        return pixels;
      }

      // ── Slide in ────────────────────────────────────────────────
      case TextEffect.slideIn: {
        final maxW   = _maxTextWidth();
        if (maxW == 0) return _renderBase();
        // Slide in over 0.5 s (fps/2 frames), then hold.
        final slideFrames = (fps * 0.8).round();
        final progress    = math.min(frame / slideFrames, 1.0);
        // Eased progress (ease-out cubic)
        final eased = 1.0 - math.pow(1.0 - progress, 3).toDouble();
        // Start offscreen right, end at center
        final font     = _font;
        final textW    = maxW;
        final centerX  = ((64 - textW) / 2).round();
        final startX   = 64;
        final currentX = (startX + (centerX - startX) * eased).round();
        return _renderBase(scrollOffsetX: currentX);
      }

      // ── Bounce ──────────────────────────────────────────────────
      case TextEffect.bounce: {
        final maxW  = _maxTextWidth();
        if (maxW == 0) return _renderBase();
        final range = math.max(0, _kCols - maxW);
        // Ping-pong over `range` pixels
        final period = fps * 2; // full cycle
        final t      = (frame % period) / period;
        final pingpong = t < 0.5 ? t * 2 : (1.0 - t) * 2;
        final offsetX = (pingpong * range).round();
        return _renderBase(scrollOffsetX: offsetX);
      }
    }
  }

  // ── LED content ────────────────────────────────────────────────

  LedMatrixContent _buildLedContent() =>
      _BitmapTextLedContent(bytes: _renderAnimated());

  // ── Send to device ─────────────────────────────────────────────

  Future<void> _sendToDevice() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (bleManager.state != FrameonConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No device connected.',
            style: TextStyle(fontFamily: 'monospace')),
      ));
      return;
    }

    setState(() { _isSending = true; _transferProgress = 0; });

    final sub = bleService.progressStream.listen((p) {
      if (mounted) setState(() => _transferProgress = p.progress);
    });

    try {
      if (_effect == TextEffect.none) {
        // Static — send a single frame
        final bytes = _renderBase();
        final frame = FrameData(bytes: bytes, durationMs: 0);
        await bleService.setMode(kModePixelArt);
        await bleService.sendSequence(FrameSequence.still(frame));
      } else {
        // Animated — build a frame sequence (~1 s of animation)
        final fps        = _effect.fps;
        final totalTicks = fps * 2; // 2-second loop
        final frames     = <FrameData>[];
        final savedTick  = _tick;
        for (int t = 0; t < totalTicks; t++) {
          _tick = t;
          final bytes = _renderAnimated();
          frames.add(FrameData(
            bytes: bytes,
            durationMs: (1000 / fps).round(),
          ));
        }
        _tick = savedTick;
        await bleService.setMode(kModePixelArt);
        await bleService.sendSequence(FrameSequence(frames: frames, isAnimated: true));
      }
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
      if (mounted) setState(() { _isSending = false; _transferProgress = 0; });
    }
  }

  // ── Build ──────────────────────────────────────────────────────

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
        if (_isSending)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TransferProgressBar(
              progress: _transferProgress,
              label: 'TRANSMITTING',
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

  // ── Header ─────────────────────────────────────────────────────

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
        Text('FONT TEXT', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: colors.textPrimary,
          fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        Text('BITMAP · PIXEL PERFECT', style: TextStyle(
          fontSize: 11, color: colors.textMuted,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        _Badge(label: _font.name.toUpperCase(), color: colors.accentYellow),
        const SizedBox(width: 8),
        const ThemeToggleButton(),
      ]),
    );
  }

  // ── Main panel ─────────────────────────────────────────────────

  Widget _buildMainPanel(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFontPicker(colors),
          const SizedBox(height: 20),
          _buildMatrixPreview(colors),
          const SizedBox(height: 20),
          _buildEffectPicker(colors),
        ],
      ),
    );
  }

  // ── Font picker ────────────────────────────────────────────────

  Widget _buildFontPicker(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('FONT', colors),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: LedFontLibrary.all.map((font) {
            final active = font.id == _fontId;
            return GestureDetector(
              onTap: () => setState(() {
                _fontId = font.id;
                for (int i = font.maxLines; i < 4; i++) {
                  _rows[i] = _rows[i].copyWith(enabled: false);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: active
                      ? colors.accentYellow.withValues(alpha: 0.10)
                      : Colors.transparent,
                  border: Border.all(
                    color: active ? colors.accentYellow : colors.border,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(font.name, style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: active
                          ? colors.accentYellow
                          : colors.textSecondary,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    )),
                    Text(
                      '${font.charHeight}px · ${font.maxLines} lines',
                      style: TextStyle(
                        fontSize: 8,
                        color: colors.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _font.description,
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
            fontFamily: 'monospace',
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ── Matrix preview ─────────────────────────────────────────────

  Widget _buildMatrixPreview(AppColors colors) {
    final activeCount = _rows
        .take(_font.maxLines)
        .where((r) => r.enabled && r.text.isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('MATRIX PREVIEW', colors),
        const SizedBox(height: 10),
        LedMatrixPreview(
          height: 200,
          label: '64 × 32  ·  ${_font.name}  ·  '
              '${_font.charHeight}px cap  ·  $activeCount active rows'
              '${_effect != TextEffect.none ? "  ·  ${_effect.label}" : ""}',
          content: _buildLedContent(),
        ),
      ],
    );
  }

  // ── Effect picker ──────────────────────────────────────────────

  Widget _buildEffectPicker(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('ANIMATION EFFECT', colors),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: TextEffect.values.map((fx) {
            final active = _effect == fx;
            // Color-code effect types
            final accentColor = switch (fx) {
              TextEffect.none        => colors.textMuted,
              TextEffect.scrollLeft  => colors.accentBlue,
              TextEffect.scrollRight => colors.accentBlue,
              TextEffect.blink       => colors.accentYellow,
              TextEffect.pulse       => const Color(0xFF00FF41),
              TextEffect.glitch      => const Color(0xFFFF2D2D),
              TextEffect.slideIn     => const Color(0xFFBF00FF),
              TextEffect.bounce      => const Color(0xFFFF6600),
            };
            return GestureDetector(
              onTap: () {
                setState(() => _effect = fx);
                _startOrStopAnimation();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: active
                      ? accentColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: active ? accentColor : colors.border,
                    width: active ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(fx.label, style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active ? accentColor : colors.textSecondary,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                )),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _effect.description,
          style: TextStyle(
            fontSize: 9,
            color: colors.textMuted,
            fontFamily: 'monospace',
            fontStyle: FontStyle.italic,
          ),
        ),
        // Scroll speed slider — only shown for scroll effects
        if (_effect == TextEffect.scrollLeft ||
            _effect == TextEffect.scrollRight) ...[
          const SizedBox(height: 12),
          _buildScrollSpeedRow(colors),
        ],
      ],
    );
  }

  Widget _buildScrollSpeedRow(AppColors colors) {
    return Row(
      children: [
        _SectionLabel('SPEED', colors),
        const SizedBox(width: 12),
        ...List.generate(4, (i) {
          final speed = i + 1;
          final active = _scrollSpeed == speed;
          return GestureDetector(
            onTap: () => setState(() => _scrollSpeed = speed),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.only(right: 6),
              width: 32,
              height: 24,
              decoration: BoxDecoration(
                color: active
                    ? colors.accentBlue.withValues(alpha: 0.15)
                    : Colors.transparent,
                border: Border.all(
                  color: active ? colors.accentBlue : colors.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text('${speed}×', style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: active ? colors.accentBlue : colors.textMuted,
                  fontFamily: 'monospace',
                )),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Right panel ────────────────────────────────────────────────

  Widget _buildRightPanel(AppColors colors) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('TEXT ROWS', colors),
            const SizedBox(height: 10),
            ..._buildRowEditors(colors),
            const SizedBox(height: 20),
            if (_selectedRow < _font.maxLines) ...[
              _buildRowOptions(colors),
              const SizedBox(height: 20),
            ],
            _ActionButton(
              label: _isSending ? 'SENDING...' : 'SEND TO DEVICE',
              color: colors.accentBlue,
              enabled: !_isSending,
              onTap: _sendToDevice,
            ),
          ],
        ),
      ),
    );
  }

  // ── Row editors ────────────────────────────────────────────────

  List<Widget> _buildRowEditors(AppColors colors) {
    return List.generate(4, (i) {
      final isAvailable = i < _font.maxLines;
      final cfg         = _rows[i];
      final isSelected  = _selectedRow == i && isAvailable;

      return GestureDetector(
        onTap: isAvailable
            ? () => setState(() {
                  _selectedRow = i;
                  if (!cfg.enabled) {
                    _rows[i] = cfg.copyWith(enabled: true);
                  }
                })
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? cfg.color.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? cfg.color
                  : isAvailable
                      ? colors.border
                      : colors.border.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: isAvailable && cfg.enabled
                    ? cfg.color.withValues(alpha: 0.15)
                    : colors.border.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text('${i + 1}', style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isAvailable && cfg.enabled
                      ? cfg.color
                      : colors.textMuted,
                  fontFamily: 'monospace',
                )),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: isSelected
                  ? TextField(
                      controller: _controllers[i],
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 12,
                        color: cfg.color,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Row ${i + 1} text...',
                        hintStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        border: InputBorder.none,
                      ),
                    )
                  : Text(
                      cfg.text.isEmpty ? '— empty —' : cfg.text,
                      style: TextStyle(
                        fontSize: 11,
                        color: isAvailable && cfg.enabled
                            ? (cfg.text.isEmpty
                                ? colors.textMuted
                                : cfg.color)
                            : colors.textMuted.withValues(alpha: 0.4),
                        fontFamily: 'monospace',
                        fontStyle: cfg.text.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
            ),
            if (isAvailable)
              GestureDetector(
                onTap: () => setState(() {
                  _rows[i] = cfg.copyWith(enabled: !cfg.enabled);
                }),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: cfg.enabled ? cfg.color : colors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            else
              Text('N/A', style: TextStyle(
                fontSize: 8,
                color: colors.textMuted.withValues(alpha: 0.4),
                fontFamily: 'monospace',
              )),
          ]),
        ),
      );
    });
  }

  // ── Row options: color + alignment ────────────────────────────

  Widget _buildRowOptions(AppColors colors) {
    final cfg = _rows[_selectedRow];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('ROW ${_selectedRow + 1} COLOR', colors),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: _kColors.map((c) {
            final sel = cfg.color == c;
            return GestureDetector(
              onTap: () => setState(() {
                _rows[_selectedRow] = cfg.copyWith(color: c);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.2),
                  border: Border.all(
                    color: sel ? c : colors.border,
                    width: sel ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: sel
                      ? [BoxShadow(
                          color: c.withValues(alpha: 0.5), blurRadius: 6)]
                      : null,
                ),
                child: Center(
                  child: Container(
                    width: 10, height: 10,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _SectionLabel('ROW ${_selectedRow + 1} ALIGNMENT', colors),
        const SizedBox(height: 10),
        _buildAlignSelector(colors, cfg),
      ],
    );
  }

  Widget _buildAlignSelector(AppColors colors, _RowConfig cfg) {
    const options = [
      (BitmapAlign.left,   Icons.align_horizontal_left,   'L'),
      (BitmapAlign.center, Icons.align_horizontal_center, 'C'),
      (BitmapAlign.right,  Icons.align_horizontal_right,  'R'),
    ];
    return Row(
      children: options.map((o) {
        final active = cfg.align == o.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _rows[_selectedRow] = cfg.copyWith(align: o.$1);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? colors.accent.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border.all(
                  color: active ? colors.accent : colors.border,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(o.$2,
                  size: 14,
                  color: active ? colors.accent : colors.textMuted),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Status bar ─────────────────────────────────────────────────

  Widget _buildStatusBar(AppColors colors) {
    final activeRows = _rows
        .take(_font.maxLines)
        .where((r) => r.enabled && r.text.isNotEmpty)
        .length;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('FONT', _font.name.toUpperCase(),
            colors.accentYellow, colors),
        const SizedBox(width: 24),
        _StatusItem('CAP', '${_font.charHeight}px',
            colors.textSecondary, colors),
        const SizedBox(width: 24),
        _StatusItem('ROWS', '$activeRows/${_font.maxLines}',
            colors.accent, colors),
        const SizedBox(width: 24),
        _StatusItem('FX', _effect.label,
            _effect == TextEffect.none ? colors.textMuted : colors.accentBlue,
            colors),
        const Spacer(),
        Flexible(
          child: Text(
            _font.description,
            style: TextStyle(
                fontSize: 9,
                color: colors.textMuted,
                fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Bitmap LED content ────────────────────────────────────────────────────────

class _BitmapTextLedContent implements LedMatrixContent {
  final List<int> bytes;
  const _BitmapTextLedContent({required this.bytes});

  @override
  void paint(Canvas canvas, Size size, double dotSize) {
    final dotW = size.width  / kLedCols;
    final dotH = size.height / kLedRows;
    for (int row = 0; row < kLedRows; row++) {
      drawLedRowFromRgb565(canvas, bytes, row, dotW, dotH, dotSize);
    }
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

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
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