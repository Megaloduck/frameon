import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import 'pixel_canvas_painter.dart';
import 'pixel_canvas_controller.dart';

/// A compact widget that shows a real-time preview of the LED matrix.
class PixelCanvasPreview extends StatelessWidget {
  final PixelCanvasController controller;
  final AppColors colors;

  const PixelCanvasPreview({
    super.key,
    required this.controller,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LED PREVIEW', style: TextStyle(
              fontSize: 9, letterSpacing: 2.0, color: colors.textMuted,
              fontWeight: FontWeight.bold, fontFamily: 'monospace',
            )),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.05),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: AspectRatio(
                  aspectRatio: kCols / kRows,
                  child: CustomPaint(
                    painter: PixelPreviewPainter(pixels: controller.pixels),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Actual ${kRows}×${kCols} ratio',
              style: TextStyle(
                fontSize: 9,
                color: colors.textMuted,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        );
      },
    );
  }
}