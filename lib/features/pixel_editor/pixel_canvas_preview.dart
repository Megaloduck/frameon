import 'package:flutter/material.dart';
import 'pixel_canvas_painter.dart';
import 'pixel_canvas_controller.dart';

/// A compact widget that shows a real-time preview of the LED matrix.
class PixelCanvasPreview extends StatelessWidget {
  final PixelCanvasController controller;

  const PixelCanvasPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('LED PREVIEW'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1A2A1A)),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF41).withValues(alpha: 0.05),
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
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF333333),
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        letterSpacing: 2.0,
        color: Color(0xFF333333),
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
  }
}