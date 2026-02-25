import 'dart:convert';
import 'package:flutter/material.dart';

const int kRows = 32;
const int kCols = 64;
const int kTotal = kRows * kCols;

enum PixelTool { draw, erase, fill, eyedrop }

class PixelCanvasController extends ChangeNotifier {
  // Pixel grid: each entry is a Color (Colors.black = off)
  List<Color> _pixels = List.filled(kTotal, Colors.black);
  List<Color> get pixels => List.unmodifiable(_pixels);

  Color _activeColor = const Color(0xFF00FF41);
  Color get activeColor => _activeColor;

  PixelTool _tool = PixelTool.draw;
  PixelTool get tool => _tool;

  // Undo/redo history
  final List<List<Color>> _history = [List.filled(kTotal, Colors.black)];
  int _historyIndex = 0;

  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;

  int get litPixelCount => _pixels.where((c) => c != Colors.black).length;

  // ── Tool & Color ──────────────────────────────────────────────

  void setTool(PixelTool t) {
    _tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    _activeColor = c;
    notifyListeners();
  }

  // ── Drawing ───────────────────────────────────────────────────

  void applyAt(int idx, {bool pushToHistory = false}) {
    if (idx < 0 || idx >= kTotal) return;
    switch (_tool) {
      case PixelTool.draw:
        _pixels[idx] = _activeColor;
        break;
      case PixelTool.erase:
        _pixels[idx] = Colors.black;
        break;
      case PixelTool.fill:
        _floodFill(idx, _pixels[idx], _activeColor);
        break;
      case PixelTool.eyedrop:
        _activeColor = _pixels[idx];
        _tool = PixelTool.draw;
        break;
    }
    if (pushToHistory) _pushHistory();
    notifyListeners();
  }

  void commitStroke() {
    _pushHistory();
  }

  void _floodFill(int idx, Color target, Color fill) {
    if (target == fill) return;
    final stack = <int>[idx];
    final visited = <int>{};
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (visited.contains(cur)) continue;
      if (cur < 0 || cur >= kTotal) continue;
      if (_pixels[cur] != target) continue;
      visited.add(cur);
      _pixels[cur] = fill;
      final col = cur % kCols;
      final row = cur ~/ kCols;
      if (col > 0) stack.add(cur - 1);
      if (col < kCols - 1) stack.add(cur + 1);
      if (row > 0) stack.add(cur - kCols);
      if (row < kRows - 1) stack.add(cur + kCols);
    }
  }

  // ── History ───────────────────────────────────────────────────

  void _pushHistory() {
    // Trim redo branch
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(List<Color>.from(_pixels));
    if (_history.length > 50) _history.removeAt(0);
    _historyIndex = _history.length - 1;
  }

  void undo() {
    if (!canUndo) return;
    _historyIndex--;
    _pixels = List<Color>.from(_history[_historyIndex]);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _historyIndex++;
    _pixels = List<Color>.from(_history[_historyIndex]);
    notifyListeners();
  }

  // ── Utility ───────────────────────────────────────────────────

  void clear() {
    _pixels = List.filled(kTotal, Colors.black);
    _pushHistory();
    notifyListeners();
  }

  /// Returns pixel index from a local offset within the canvas widget.
  int? indexFromOffset(Offset offset, double pixelSize) {
    final col = (offset.dx / pixelSize).floor();
    final row = (offset.dy / pixelSize).floor();
    if (col < 0 || col >= kCols || row < 0 || row >= kRows) return null;
    return row * kCols + col;
  }

  /// Export as JSON for BLE transmission to ESP32.
  String exportJson() {
    final hexPixels = _pixels
        .map((c) => '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}')
        .toList();
    return jsonEncode({
      'width': kCols,
      'height': kRows,
      'pixels': hexPixels,
    });
  }

  /// Export as RGB565 bytes for direct ESP32 rendering.
  List<int> exportRgb565() {
    final bytes = <int>[];
    for (final c in _pixels) {
      final r = (c.red >> 3) & 0x1F;
      final g = (c.green >> 2) & 0x3F;
      final b = (c.blue >> 3) & 0x1F;
      final word = (r << 11) | (g << 5) | b;
      bytes.add((word >> 8) & 0xFF);
      bytes.add(word & 0xFF);
    }
    return bytes;
  }
}