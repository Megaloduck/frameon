import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pixel_canvas_controller.dart';
import 'pixel_canvas_painter.dart';
import 'pixel_canvas_preview.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_uuids.dart';
import '../frame_encoder/frame_model.dart';
import '../ui/connection_status.dart';

// ── Palettes ──────────────────────────────────────────────────────────────────

const Map<String, List<Color>> kPalettes = {
  'NEON': [
    Color(0xFFFF0080), Color(0xFF00FF41), Color(0xFF00B4FF), Color(0xFFFFE600),
    Color(0xFFFF6600), Color(0xFFBF00FF), Color(0xFF00FFD1), Color(0xFFFF2D2D),
  ],
  'WARM': [
    Color(0xFFFF4500), Color(0xFFFF8C00), Color(0xFFFFD700), Color(0xFFFF6347),
    Color(0xFFDC143C), Color(0xFFFF1493), Color(0xFFFF69B4), Color(0xFFFFA07A),
  ],
  'COOL': [
    Color(0xFF00CED1), Color(0xFF1E90FF), Color(0xFF7B68EE), Color(0xFF00FA9A),
    Color(0xFF40E0D0), Color(0xFF87CEEB), Color(0xFF6495ED), Color(0xFF9370DB),
  ],
  'MONO': [
    Color(0xFFFFFFFF), Color(0xFFCCCCCC), Color(0xFF999999), Color(0xFF666666),
    Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF), Color(0xFFFFFF00),
  ],
};

const List<double> kZoomLevels = [6, 8, 10, 12, 14, 16];

// ── Main Screen ───────────────────────────────────────────────────────────────

class PixelCanvasEditor extends ConsumerStatefulWidget {
  const PixelCanvasEditor({super.key});

  @override
  ConsumerState<PixelCanvasEditor> createState() => _PixelCanvasEditorState();
}

class _PixelCanvasEditorState extends ConsumerState<PixelCanvasEditor> {
  final _controller = PixelCanvasController();
  double _zoom = 12;
  String _palette = 'NEON';
  bool _previewOn = true;
  int? _lastIdx;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Keyboard shortcuts ────────────────────────────────────────

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyD) _controller.setTool(PixelTool.draw);
    if (key == LogicalKeyboardKey.keyE) _controller.setTool(PixelTool.erase);
    if (key == LogicalKeyboardKey.keyF) _controller.setTool(PixelTool.fill);
    if (key == LogicalKeyboardKey.keyI) _controller.setTool(PixelTool.eyedrop);
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && key == LogicalKeyboardKey.keyZ) _controller.undo();
    if (ctrl && key == LogicalKeyboardKey.keyY) _controller.redo();
  }

  // ── Pointer events ────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e, BoxConstraints constraints) {
    final idx = _controller.indexFromOffset(e.localPosition, _zoom);
    if (idx == null) return;
    _lastIdx = idx;
    _controller.applyAt(idx);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final idx = _controller.indexFromOffset(e.localPosition, _zoom);
    if (idx == null || idx == _lastIdx) return;
    _lastIdx = idx;
    _controller.applyAt(idx);
  }

  void _onPointerUp(PointerUpEvent e) {
    _controller.commitStroke();
    _lastIdx = null;
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bleManager = ref.watch(bleManagerProvider);
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Column(
          children: [
            _buildHeader(),
            ConnectionStatusBar(
              manager: bleManager,
              onTap: () => DeviceScannerSheet.show(context, bleManager),
            ),
            Expanded(
              child: Row(
                children: [
                  _buildLeftToolbar(),
                  Expanded(child: _buildCanvas()),
                  _buildRightPanel(),
                ],
              ),
            ),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00FF41), Color(0xFF00B4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Text('F', style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14,
              )),
            ),
          ),
          const SizedBox(width: 10),
          const Text('FRAMEON', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold,
            letterSpacing: 2, color: Colors.white, fontFamily: 'monospace',
          )),
          const SizedBox(width: 10),
          const Text('PIXEL EDITOR', style: TextStyle(
            fontSize: 11, color: Color(0xFF444444),
            letterSpacing: 1.5, fontFamily: 'monospace',
          )),
          const Spacer(),
          const Text('32 × 64 LED MATRIX', style: TextStyle(
            fontSize: 11, color: Color(0xFF444444),
            letterSpacing: 1, fontFamily: 'monospace',
          )),
          const SizedBox(width: 16),
          _HeaderButton(
            label: _previewOn ? 'PREVIEW ON' : 'PREVIEW OFF',
            active: _previewOn,
            onTap: () => setState(() => _previewOn = !_previewOn),
          ),
        ],
      ),
    );
  }

  // ── Left toolbar ──────────────────────────────────────────────

  Widget _buildLeftToolbar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Container(
        width: 68,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          border: Border(right: BorderSide(color: Color(0xFF1A1A2E))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            _ToolButton(icon: '✏️', label: 'Draw [D]',
              active: _controller.tool == PixelTool.draw,
              onTap: () => _controller.setTool(PixelTool.draw)),
            const SizedBox(height: 6),
            _ToolButton(icon: '⬜', label: 'Erase [E]',
              active: _controller.tool == PixelTool.erase,
              onTap: () => _controller.setTool(PixelTool.erase)),
            const SizedBox(height: 6),
            _ToolButton(icon: '🪣', label: 'Fill [F]',
              active: _controller.tool == PixelTool.fill,
              onTap: () => _controller.setTool(PixelTool.fill)),
            const SizedBox(height: 6),
            _ToolButton(icon: '💉', label: 'Pick [I]',
              active: _controller.tool == PixelTool.eyedrop,
              onTap: () => _controller.setTool(PixelTool.eyedrop)),
            const _Divider(),
            _IconButton(icon: '↩', tooltip: 'Undo',
              onTap: _controller.canUndo ? _controller.undo : null),
            const SizedBox(height: 6),
            _IconButton(icon: '↪', tooltip: 'Redo',
              onTap: _controller.canRedo ? _controller.redo : null),
            const _Divider(),
            _IconButton(
              icon: '✕', tooltip: 'Clear',
              color: const Color(0xFFFF2D2D),
              onTap: _controller.clear,
            ),
          ],
        ),
      ),
    );
  }

  // ── Canvas ────────────────────────────────────────────────────

  Widget _buildCanvas() {
    final canvasW = kCols * _zoom;
    final canvasH = kRows * _zoom;

    return Stack(
      children: [
        // Scrollable canvas
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF1A2A1A)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF41).withValues(alpha: 0.06),
                        blurRadius: 60, spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Listener(
                      onPointerDown: (e) => _onPointerDown(
                        e, BoxConstraints.tight(Size(canvasW, canvasH))),
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      child: ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) => CustomPaint(
                          size: Size(canvasW, canvasH),
                          painter: PixelCanvasPainter(
                            pixels: _controller.pixels,
                            pixelSize: _zoom,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Zoom controls
        Positioned(
          top: 16, right: 16,
          child: _buildZoomControls(),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border.all(color: const Color(0xFF1A1A2E)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ZOOM ', style: TextStyle(
            fontSize: 10, color: Color(0xFF444444),
            letterSpacing: 1, fontFamily: 'monospace',
          )),
          ...kZoomLevels.map((z) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => setState(() => _zoom = z),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _zoom == z
                      ? const Color(0xFF00FF4122)
                      : Colors.transparent,
                  border: Border.all(
                    color: _zoom == z
                        ? const Color(0xFF00FF41)
                        : const Color(0xFF222222),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${z.toInt()}×',
                  style: TextStyle(
                    fontSize: 10,
                    color: _zoom == z
                        ? const Color(0xFF00FF41)
                        : const Color(0xFF444444),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  // ── Right panel ───────────────────────────────────────────────

  Widget _buildRightPanel() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(left: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActiveColor(),
              const SizedBox(height: 20),
              _buildPaletteSection(),
              const SizedBox(height: 20),
              if (_previewOn) ...[
                PixelCanvasPreview(controller: _controller),
                const SizedBox(height: 20),
              ],
              _buildCanvasInfo(),
              const SizedBox(height: 20),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveColor() {
    final c = _controller.activeColor;
    final hex = '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final rgb = 'RGB(${c.red},${c.green},${c.blue})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('ACTIVE COLOR'),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF333333)),
              boxShadow: [BoxShadow(
                color: c.withValues(alpha: 0.4), blurRadius: 12,
              )],
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hex, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: Colors.white, letterSpacing: 1, fontFamily: 'monospace',
            )),
            const SizedBox(height: 2),
            Text(rgb, style: const TextStyle(
              fontSize: 10, color: Color(0xFF555555), fontFamily: 'monospace',
            )),
          ]),
        ]),
      ],
    );
  }

  Widget _buildPaletteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PALETTE'),
        const SizedBox(height: 8),
        // Palette tabs
        Row(
          children: kPalettes.keys.map((name) {
            final active = _palette == name;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _palette = name),
                child: Container(
                  margin: const EdgeInsets.only(right: 3),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF00FF4122) : Colors.transparent,
                    border: Border.all(
                      color: active ? const Color(0xFF00FF41) : const Color(0xFF222222),
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      color: active ? const Color(0xFF00FF41) : const Color(0xFF444444),
                      letterSpacing: 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Color swatches
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          children: (kPalettes[_palette] ?? []).map((c) {
            final selected = _controller.activeColor == c;
            return GestureDetector(
              onTap: () => _controller.setColor(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCanvasInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('CANVAS INFO'),
        const SizedBox(height: 8),
        _InfoRow('Dimensions', '$kRows × $kCols px'),
        _InfoRow('Lit pixels', '${_controller.litPixelCount}'),
        _InfoRow('History', '${_controller.canUndo ? "can undo" : "–"}'),
      ],
    );
  }

  Widget _buildActions() {
    return Column(children: [
      _ActionButton(
        label: 'EXPORT JSON',
        color: const Color(0xFF00FF41),
        onTap: () {
          final json = _controller.exportJson();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported ${json.length} bytes',
                style: const TextStyle(fontFamily: 'monospace')),
              backgroundColor: const Color(0xFF0D0D1A),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ActionButton(
        label: 'SEND TO DEVICE',
        color: const Color(0xFF00B4FF),
        onTap: _sendToDevice,
      ),
      const SizedBox(height: 8),
      _ActionButton(
        label: 'CLEAR CANVAS',
        color: const Color(0xFFFF2D2D),
        outlined: true,
        onTap: _controller.clear,
      ),
    ]);
  }

  Future<void> _sendToDevice() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (bleManager.state != FrameonConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No device connected. Tap the status bar to connect.',
            style: TextStyle(fontFamily: 'monospace')),
        backgroundColor: Color(0xFF1A0A0A),
      ));
      return;
    }

    final bytes = _controller.exportRgb565();
    final frame = FrameData(bytes: bytes, durationMs: 0);
    final sequence = FrameSequence.still(frame);

    try {
      await bleService.setMode(kModePixelArt);
      await bleService.sendSequence(sequence);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Sent to device',
              style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: Color(0xFF0A1A0A),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'monospace')),
          backgroundColor: const Color(0xFF1A0A0A),
        ));
      }
    }
  }

  // ── Status bar ────────────────────────────────────────────────

  Widget _buildStatusBar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Container(
        height: 28,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _StatusItem('TOOL', _controller.tool.name.toUpperCase(),
              const Color(0xFF00FF41)),
          const SizedBox(width: 24),
          _StatusItem('COLOR',
            '#${_controller.activeColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            _controller.activeColor),
          const SizedBox(width: 24),
          _StatusItem('ZOOM', '${_zoom.toInt()}×', const Color(0xFF666666)),
          const Spacer(),
          const Text(
            'D · E · F · I — TOOLS    CTRL+Z · CTRL+Y — UNDO/REDO',
            style: TextStyle(
              fontSize: 9, color: Color(0xFF333333),
              letterSpacing: 0.8, fontFamily: 'monospace',
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    fontSize: 9, letterSpacing: 2.0, color: Color(0xFF333333),
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _ToolButton extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon, required this.label,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00FF4122) : Colors.transparent,
          border: Border.all(
            color: active ? const Color(0xFF00FF41) : const Color(0xFF222222),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
      ),
    ),
  );
}

class _IconButton extends StatelessWidget {
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;

  const _IconButton({
    required this.icon, required this.tooltip,
    this.onTap, this.color = const Color(0xFF888888),
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1.0,
        child: Container(
          width: 44, height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF333333)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(icon, style: TextStyle(fontSize: 15, color: color)),
          ),
        ),
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(height: 1, width: 40, color: const Color(0xFF1A1A2E)),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 11, color: Color(0xFF444444), fontFamily: 'monospace',
        )),
        Text(value, style: const TextStyle(
          fontSize: 11, color: Color(0xFF888888), fontFamily: 'monospace',
        )),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionButton({
    required this.label, required this.color, required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.1),
        border: Border.all(
          color: outlined ? color.withValues(alpha: 0.3) : color,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold,
          color: outlined ? color.withValues(alpha: 0.5) : color,
          letterSpacing: 1.5, fontFamily: 'monospace',
        ),
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.label, required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF00FF4122) : Colors.transparent,
        border: Border.all(
          color: active ? const Color(0xFF00FF41) : const Color(0xFF333333),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10,
        color: active ? const Color(0xFF00FF41) : const Color(0xFF555555),
        letterSpacing: 1, fontFamily: 'monospace',
      )),
    ),
  );
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatusItem(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: const TextStyle(
      fontSize: 10, color: Color(0xFF333333),
      letterSpacing: 0.8, fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor,
      letterSpacing: 0.8, fontFamily: 'monospace',
    )),
  ]);
}