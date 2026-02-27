import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'pixel_canvas_controller.dart';

/// Renders the 32×64 LED matrix grid with per-pixel glow.
class PixelCanvasPainter extends CustomPainter {
  final List<Color> pixels;
  final double pixelSize;
  final bool showGrid;
  final bool isDark;

  const PixelCanvasPainter({
    required this.pixels,
    required this.pixelSize,
    this.showGrid = true,
    this.isDark = true,
  });

  // Canvas background — near-black in dark mode, very dark grey in light mode
  // so the LED glow still reads well against it.
  Color get _bgColor => isDark
      ? const Color(0xFF080810)
      : const Color(0xFF111118);

  // Grid lines — subtle in both modes
  Color get _gridColor => isDark
      ? const Color(0xFF1A1A2E)
      : const Color(0xFF2A2A3A);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    if (showGrid) _drawGrid(canvas, size);
    _drawPixels(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _bgColor,
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int col = 0; col <= kCols; col++) {
      final x = col * pixelSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int row = 0; row <= kRows; row++) {
      final y = row * pixelSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawPixels(Canvas canvas) {
    for (int i = 0; i < pixels.length; i++) {
      final color = pixels[i];
      if (color == Colors.black) continue;

      final col = i % kCols;
      final row = i ~/ kCols;
      final rect = Rect.fromLTWH(
        col * pixelSize + 1,
        row * pixelSize + 1,
        pixelSize - 1,
        pixelSize - 1,
      );

      canvas.drawRect(rect, Paint()..color = color);

      if (pixelSize >= 8) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, pixelSize * 0.55);
        canvas.drawRect(rect.inflate(pixelSize * 0.15), glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(PixelCanvasPainter oldDelegate) {
    return oldDelegate.pixels != pixels ||
        oldDelegate.pixelSize != pixelSize ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.isDark != isDark;
  }
}

/// Lightweight painter for the mini preview (no grid, no glow).
/// The LED canvas itself is always rendered on black regardless of app theme —
/// that matches a real LED matrix display.
class PixelPreviewPainter extends CustomPainter {
  final List<Color> pixels;

  const PixelPreviewPainter({required this.pixels});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    final pw = size.width / kCols;
    final ph = size.height / kRows;

    for (int i = 0; i < pixels.length; i++) {
      final color = pixels[i];
      if (color == Colors.black) continue;
      final col = i % kCols;
      final row = i ~/ kCols;
      canvas.drawRect(
        Rect.fromLTWH(col * pw, row * ph, pw, ph),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(PixelPreviewPainter oldDelegate) =>
      oldDelegate.pixels != pixels;
}