import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_uuids.dart';
import '../frame_encoder/frame_model.dart';
import '../ui/connection_status.dart';
import '../ui/led_matrix_preview.dart';
import '../ui/theme_switcher.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kCols = 64;
const int _kRows = 32;

// ── Model ─────────────────────────────────────────────────────────────────────

class _LoadedFont {
  final String name;       // filename without extension
  final Uint8List bytes;
  final String fontFamily; // unique key registered with Flutter

  const _LoadedFont({
    required this.name,
    required this.bytes,
    required this.fontFamily,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class FontTextScreen extends ConsumerStatefulWidget {
  const FontTextScreen({super.key});

  @override
  ConsumerState<FontTextScreen> createState() => _FontTextScreenState();
}

class _FontTextScreenState extends ConsumerState<FontTextScreen> {
  // ── Font state ─────────────────────────────────────────────────
  _LoadedFont? _font;
  bool _loadingFont = false;

  // ── Text / style ───────────────────────────────────────────────
  final _textCtrl = TextEditingController(text: 'HELLO');
  double _fontSize = 20;
  Color _textColor = const Color(0xFF00FF41);
  TextAlign _align = TextAlign.center;
  bool _bold = false;
  bool _italic = false;

  // Vertical offset so users can nudge text up/down on the 32-row panel
  double _offsetY = 0;

  // ── Rendered output ────────────────────────────────────────────
  List<int>? _rgb565Bytes;
  bool _rendering = false;

  // ── Transfer ───────────────────────────────────────────────────
  bool _isSending = false;
  double _transferProgress = 0;

  // ── Preset colors ──────────────────────────────────────────────
  static const _kColors = [
    Color(0xFF00FF41), // green
    Color(0xFFFFFFFF), // white
    Color(0xFF00B4FF), // cyan
    Color(0xFFFFE600), // yellow
    Color(0xFFFF2D2D), // red
    Color(0xFFFF00CC), // pink
    Color(0xFFBF00FF), // purple
    Color(0xFFFF6600), // orange
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_scheduleRender);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // ── Font loading ───────────────────────────────────────────────

  Future<void> _pickFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _loadingFont = true);

    try {
      // Give the font a unique family name so multiple loads don't clash.
      final familyName = 'UserFont_${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      final loader = FontLoader(familyName)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();

      setState(() {
        _font = _LoadedFont(
          name: file.name.replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), ''),
          bytes: bytes,
          fontFamily: familyName,
        );
        _loadingFont = false;
      });

      await _render();
    } catch (e) {
      setState(() => _loadingFont = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load font: $e',
              style: const TextStyle(fontFamily: 'monospace')),
        ));
      }
    }
  }

  void _clearFont() {
    setState(() {
      _font = null;
      _rgb565Bytes = null;
    });
  }

  // ── Rendering ──────────────────────────────────────────────────

  void _scheduleRender() {
    if (_rendering) return;
    _render();
  }

  Future<void> _render() async {
    if (_textCtrl.text.isEmpty) {
      setState(() => _rgb565Bytes = null);
      return;
    }

    setState(() => _rendering = true);

    try {
      final bytes = await _renderToRgb565(
        text: _textCtrl.text,
        fontFamily: _font?.fontFamily ?? 'monospace',
        fontSize: _fontSize,
        color: _textColor,
        bold: _bold,
        italic: _italic,
        align: _align,
        offsetY: _offsetY,
      );
      if (mounted) setState(() => _rgb565Bytes = bytes);
    } catch (e) {
      // Silently ignore render errors during typing
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// Renders [text] onto a 64×32 canvas and returns RGB565 bytes.
  ///
  /// Uses Flutter's paragraph/canvas API so any loaded font — including
  /// your custom .ttf/.otf — is rendered faithfully at the LED resolution.
  static Future<List<int>> _renderToRgb565({
    required String text,
    required String fontFamily,
    required double fontSize,
    required Color color,
    required bool bold,
    required bool italic,
    required TextAlign align,
    required double offsetY,
  }) async {
    const w = _kCols;
    const h = _kRows;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

    // Black background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.black,
    );

    // Build paragraph
    final style = ui.ParagraphStyle(
      textAlign: align,
      fontFamily: fontFamily,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
      maxLines: 2,
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ))
      ..addText(text);

    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: w.toDouble()));

    // Centre vertically (+ user offset)
    final textH = paragraph.height;
    final dy = ((h - textH) / 2 + offsetY).clamp(-(h / 2), h.toDouble());
    canvas.drawParagraph(paragraph, Offset(0, dy));

    final picture = recorder.endRecording();

    // Rasterise to image at exact matrix resolution
    final image = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    image.dispose();

    if (byteData == null) throw Exception('Failed to rasterise text');

    // Convert RGBA → RGB565 big-endian
    final rgba = byteData.buffer.asUint8List();
    final rgb565 = <int>[];
    for (int i = 0; i < rgba.length; i += 4) {
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final word = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
      rgb565.add((word >> 8) & 0xFF);
      rgb565.add(word & 0xFF);
    }
    return rgb565;
  }

  // ── Send to device ─────────────────────────────────────────────

  Future<void> _sendToDevice() async {
    if (_rgb565Bytes == null) return;
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
      final frame = FrameData(bytes: _rgb565Bytes!, durationMs: 0);
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
          letterSpacing: 2, color: colors.textPrimary, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        Text('CUSTOM TTF · OTF', style: TextStyle(
          fontSize: 11, color: colors.textMuted,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        if (_font != null)
          _Badge(label: _font!.name.toUpperCase(), color: colors.accentYellow),
        const SizedBox(width: 8),
        const ThemeToggleButton(),
      ]),
    );
  }

  // ── Main panel ─────────────────────────────────────────────────

  Widget _buildMainPanel(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        // Font picker card
        _buildFontCard(colors),
        const SizedBox(height: 24),
        // Matrix preview
        _buildMatrixPreview(colors),
      ]),
    );
  }

  Widget _buildFontCard(AppColors colors) {
    return GestureDetector(
      onTap: _font == null ? _pickFont : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(
            color: _font != null
                ? colors.accentYellow.withValues(alpha: 0.4)
                : colors.accent.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _loadingFont
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: colors.accent, strokeWidth: 1.5),
                ),
                const SizedBox(width: 12),
                Text('Loading font...', style: TextStyle(
                  fontSize: 11, color: colors.accent,
                  letterSpacing: 1, fontFamily: 'monospace',
                )),
              ])
            : _font == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.font_download_outlined,
                        color: colors.textMuted, size: 36),
                    const SizedBox(height: 12),
                    Text('TAP TO LOAD FONT', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold,
                      color: colors.accent, letterSpacing: 2,
                      fontFamily: 'monospace',
                    )),
                    const SizedBox(height: 4),
                    Text('.ttf  ·  .otf', style: TextStyle(
                      fontSize: 10, color: colors.textMuted,
                      letterSpacing: 1, fontFamily: 'monospace',
                    )),
                    const SizedBox(height: 4),
                    Text(
                      'Any font file works — pixel fonts, display fonts, etc.',
                      style: TextStyle(
                        fontSize: 9, color: colors.textMuted,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ])
                : Row(children: [
                    Icon(Icons.font_download,
                        color: colors.accentYellow, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_font!.name, style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold,
                            color: colors.accentYellow,
                            letterSpacing: 1, fontFamily: _font!.fontFamily,
                          )),
                          Text('Custom font loaded', style: TextStyle(
                            fontSize: 9, color: colors.textMuted,
                            fontFamily: 'monospace',
                          )),
                        ],
                      ),
                    ),
                    // Swap font
                    GestureDetector(
                      onTap: _pickFont,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('CHANGE', style: TextStyle(
                          fontSize: 9, color: colors.textSecondary,
                          letterSpacing: 1, fontFamily: 'monospace',
                        )),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Remove font
                    GestureDetector(
                      onTap: _clearFont,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: colors.accentRed.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('REMOVE', style: TextStyle(
                          fontSize: 9, color: colors.accentRed,
                          letterSpacing: 1, fontFamily: 'monospace',
                        )),
                      ),
                    ),
                  ]),
      ),
    );
  }

  Widget _buildMatrixPreview(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('MATRIX PREVIEW', colors),
        const SizedBox(height: 10),
        LedMatrixPreview(
          height: 160,
          label: '64 × 32  ·  '
              '${_font != null ? _font!.name : "monospace"}'
              '  ·  ${_fontSize.round()}pt',
          content: _rgb565Bytes != null
              ? Rgb565LedContent(bytes: _rgb565Bytes!)
              : EmptyLedContent(color: colors.accent),
        ),
      ],
    );
  }

  // ── Right panel ────────────────────────────────────────────────

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
            // ── Text input ──────────────────────────────────────
            _SectionLabel('TEXT', colors),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.inputBg,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(5),
              ),
              child: TextField(
                controller: _textCtrl,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                  fontFamily: _font?.fontFamily ?? 'monospace',
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(10),
                  hintText: 'Enter text...',
                  hintStyle: TextStyle(
                    color: colors.textMuted, fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Color ───────────────────────────────────────────
            _SectionLabel('COLOR', colors),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _kColors.map((c) {
                final sel = _textColor == c;
                return GestureDetector(
                  onTap: () {
                    setState(() => _textColor = c);
                    _render();
                  },
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
                              color: c.withValues(alpha: 0.4),
                              blurRadius: 6)]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: c, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Font size ───────────────────────────────────────
            _SectionLabel('FONT SIZE  ${_fontSize.round()}pt', colors),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accent,
                inactiveTrackColor: colors.border,
                thumbColor: colors.accent,
                overlayColor: colors.accent.withValues(alpha: 0.12),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
              ),
              child: Slider(
                value: _fontSize,
                min: 6,
                max: 32,
                divisions: 26,
                onChanged: (v) => setState(() => _fontSize = v),
                onChangeEnd: (_) => _render(),
              ),
            ),

            const SizedBox(height: 12),

            // ── Vertical offset ─────────────────────────────────
            _SectionLabel(
                'VERTICAL OFFSET  ${_offsetY >= 0 ? '+' : ''}${_offsetY.round()}',
                colors),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.accentBlue,
                inactiveTrackColor: colors.border,
                thumbColor: colors.accentBlue,
                overlayColor: colors.accentBlue.withValues(alpha: 0.12),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
              ),
              child: Slider(
                value: _offsetY,
                min: -16,
                max: 16,
                divisions: 32,
                onChanged: (v) => setState(() => _offsetY = v),
                onChangeEnd: (_) => _render(),
              ),
            ),

            const SizedBox(height: 20),

            // ── Style ────────────────────────────────────────────
            _SectionLabel('STYLE', colors),
            const SizedBox(height: 10),
            Row(children: [
              _StyleToggle(
                label: 'BOLD',
                active: _bold,
                color: colors.accent,
                colors: colors,
                onTap: () { setState(() => _bold = !_bold); _render(); },
              ),
              const SizedBox(width: 8),
              _StyleToggle(
                label: 'ITALIC',
                active: _italic,
                color: colors.accentYellow,
                colors: colors,
                onTap: () { setState(() => _italic = !_italic); _render(); },
              ),
            ]),

            const SizedBox(height: 16),

            // ── Alignment ────────────────────────────────────────
            _SectionLabel('ALIGNMENT', colors),
            const SizedBox(height: 10),
            _buildAlignSelector(colors),

            const SizedBox(height: 24),

            // ── Actions ──────────────────────────────────────────
            _ActionButton(
              label: 'RENDER',
              color: colors.accent,
              onTap: _render,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: _isSending ? 'SENDING...' : 'SEND TO DEVICE',
              color: colors.accentBlue,
              enabled: _rgb565Bytes != null && !_isSending,
              onTap: _sendToDevice,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlignSelector(AppColors colors) {
    const options = [
      (TextAlign.left,   Icons.align_horizontal_left,   'L'),
      (TextAlign.center, Icons.align_horizontal_center,  'C'),
      (TextAlign.right,  Icons.align_horizontal_right,  'R'),
    ];
    return Row(
      children: options.map((o) {
        final active = _align == o.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () { setState(() => _align = o.$1); _render(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? colors.accent.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border.all(
                    color: active ? colors.accent : colors.border),
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
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('FONT',
            _font?.name.toUpperCase() ?? 'MONOSPACE',
            colors.accentYellow, colors),
        const SizedBox(width: 24),
        _StatusItem('SIZE', '${_fontSize.round()}pt',
            colors.textSecondary, colors),
        const SizedBox(width: 24),
        _StatusItem('COLOR', '#${_textColor.value.toRadixString(16)
            .padLeft(8, '0').substring(2).toUpperCase()}',
            _textColor, colors),
        const Spacer(),
        if (_rendering)
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(
                color: colors.accent, strokeWidth: 1),
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

class _StyleToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final AppColors colors;
  final VoidCallback onTap;
  const _StyleToggle({
    required this.label, required this.active,
    required this.color, required this.colors, required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
        border: Border.all(color: active ? color : colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.bold,
        color: active ? color : colors.textMuted,
        letterSpacing: 1, fontFamily: 'monospace',
      )),
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