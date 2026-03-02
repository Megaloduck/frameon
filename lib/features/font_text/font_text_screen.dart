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

class _FontTextScreenState extends ConsumerState<FontTextScreen> {
  // ── Font selection ─────────────────────────────────────────────
  LedFontId _fontId = LedFontId.matrixtype;
  LedFont get _font => LedFontLibrary.get(_fontId);

  // ── Row configs ────────────────────────────────────────────────
  // Up to 4 rows for 7px fonts, 3 rows for 8px fonts.
  // We always show 4 slots; slots beyond font.maxLines are unavailable.
  late List<_RowConfig> _rows;
  late List<TextEditingController> _controllers;

  // ── Selected row for editing ───────────────────────────────────
  int _selectedRow = 0;

  // ── Transfer ───────────────────────────────────────────────────
  bool _isSending = false;
  double _transferProgress = 0;

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
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  // ── Render to RGB565 ───────────────────────────────────────────

  List<int> _renderToRgb565() {
    final font   = _font;
    final pixels = List<int>.filled(_kCols * _kRows * 2, 0); // black

    for (int slot = 0; slot < font.maxLines && slot < 4; slot++) {
      final cfg = _rows[slot];
      if (!cfg.enabled || cfg.text.isEmpty) continue;

      final color = cfg.color;
      final r5 = (color.red   >> 3) & 0x1F;
      final g6 = (color.green >> 2) & 0x3F;
      final b5 = (color.blue  >> 3) & 0x1F;
      final word = (r5 << 11) | (g6 << 5) | b5;
      final hi = (word >> 8) & 0xFF;
      final lo = word & 0xFF;

      final rowY = font.rowY[slot];

      // Compute X start based on alignment
      final textW = font.textWidth(cfg.text);
      int startX;
      switch (cfg.align) {
        case BitmapAlign.left:
          startX = 0;
        case BitmapAlign.center:
          startX = font.centeredX(cfg.text);
        case BitmapAlign.right:
          startX = (_kCols - textW).clamp(0, _kCols - 1);
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
        if (penX >= _kCols) break;
      }
    }

    return pixels;
  }

  // ── LED content ────────────────────────────────────────────────

  LedMatrixContent _buildLedContent() =>
      _BitmapTextLedContent(bytes: _renderToRgb565());

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
      final bytes = _renderToRgb565();
      final frame = FrameData(bytes: bytes, durationMs: 0);
      await bleService.setMode(kModePixelArt);
      await bleService.sendSequence(FrameSequence.still(frame));
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
                // Disable rows that exceed the new font's line count
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
          height: 220,
          label: '64 × 32  ·  ${_font.name}  ·  '
              '${_font.charHeight}px cap  ·  $activeCount active rows',
          content: _buildLedContent(),
        ),
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
            // Row number badge
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
            // Text field (when selected) or label
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
            // Enable/disable toggle dot (or N/A for unavailable rows)
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

  // ── Row options: color + alignment for the selected row ────────

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