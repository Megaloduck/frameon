import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

const int kLedCols = 64;
const int kLedRows = 32;

// ── Content interface ─────────────────────────────────────────────────────────

abstract class LedMatrixContent {
  void paint(Canvas canvas, Size size, double dotSize);
}

// ── Main widget ───────────────────────────────────────────────────────────────

/// Renders a 64×32 LED dot-matrix panel at a strict 2:1 ratio.
///
/// IMPORTANT — always anchor with an explicit dimension:
///
///   // Inside a Column (vertically unconstrained) — anchor by height:
///   LedMatrixPreview(height: 120, content: ...)
///
///   // Inside a Row / Expanded (horizontally constrained) — anchor by width:
///   LedMatrixPreview(width: 400, content: ...)
///
/// If neither [width] nor [height] is given the widget falls back to
/// LayoutBuilder, which only works safely inside a width-bounded parent.
/// Forgetting to pass a dimension in a Column is what caused the stretch.
class LedMatrixPreview extends StatelessWidget {
  final LedMatrixContent content;
  final String? label;

  /// Anchor by width — height = width / 2.
  final double? width;

  /// Anchor by height — width = height * 2.
  final double? height;

  const LedMatrixPreview({
    super.key,
    required this.content,
    this.label,
    this.width,
    this.height,
  }) : assert(
          !(width != null && height != null),
          'Supply width OR height, not both.',
        );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (width != null || height != null) {
      final w = width  ?? height! * 2.0;
      final h = height ?? width!  / 2.0;
      return _buildColumn(colors, w, h);
    }

    // Fallback — only safe when parent constrains width.
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 200.0;
        return _buildColumn(colors, w, w / 2.0);
      },
    );
  }

  Widget _buildColumn(AppColors colors, double w, double h) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPanel(colors, w, h),
        if (label != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF00FF41).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label!,
              style: TextStyle(
                fontSize: 9,
                color: colors.textMuted,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _buildPanel(AppColors colors, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF06060E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.isDark
              ? const Color(0xFF2A2A3A)
              : const Color(0xFF1A1A28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.6 : 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF00FF41).withValues(alpha: 0.04),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          size: Size(w, h),
          painter: _LedPanelPainter(content: content),
        ),
      ),
    );
  }
}

// ── Panel painter ─────────────────────────────────────────────────────────────

class _LedPanelPainter extends CustomPainter {
  final LedMatrixContent content;
  const _LedPanelPainter({required this.content});

  @override
  void paint(Canvas canvas, Size size) {
    final dotW    = size.width  / kLedCols;
    final dotH    = size.height / kLedRows;
    final dotSize = math.min(dotW, dotH);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF06060E),
    );
    _drawOffDots(canvas, dotW, dotH, dotSize);
    content.paint(canvas, size, dotSize);
    _drawScanlines(canvas, size, dotH);
  }

  void _drawOffDots(Canvas canvas, double dotW, double dotH, double dotSize) {
    final r        = dotSize * 0.28;
    final offPaint = Paint()..color = const Color(0xFF12121E);
    for (int row = 0; row < kLedRows; row++) {
      for (int col = 0; col < kLedCols; col++) {
        canvas.drawCircle(
          Offset(col * dotW + dotW / 2, row * dotH + dotH / 2),
          r, offPaint,
        );
      }
    }
  }

  void _drawScanlines(Canvas canvas, Size size, double dotH) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.18);
    for (int row = 0; row < kLedRows; row++) {
      canvas.drawRect(
        Rect.fromLTWH(0, row * dotH + dotH * 0.78, size.width, dotH * 0.22),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LedPanelPainter old) => old.content != content;
}

// ── Shared drawing helpers ────────────────────────────────────────────────────

void drawLedDot(
  Canvas canvas,
  double col, double row,
  double dotW, double dotH, double dotSize,
  Color color, {
  bool glow = true,
}) {
  final cx = col * dotW + dotW / 2;
  final cy = row * dotH + dotH / 2;
  final r  = dotSize * 0.38;

  if (glow) {
    canvas.drawCircle(
      Offset(cx, cy), r * 2.2,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, r * 1.4),
    );
  }
  canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
  // Specular highlight
  canvas.drawCircle(
    Offset(cx - r * 0.3, cy - r * 0.3), r * 0.28,
    Paint()..color = Colors.white.withValues(alpha: 0.35),
  );
}

void drawLedRowFromRgb565(
  Canvas canvas,
  List<int> bytes, int row,
  double dotW, double dotH, double dotSize,
) {
  for (int col = 0; col < kLedCols; col++) {
    final i = (row * kLedCols + col) * 2;
    if (i + 1 >= bytes.length) break;
    final word = (bytes[i] << 8) | bytes[i + 1];
    final r = ((word >> 11) & 0x1F) << 3;
    final g = ((word >>  5) & 0x3F) << 2;
    final b =  (word        & 0x1F) << 3;
    if (r == 0 && g == 0 && b == 0) continue;
    drawLedDot(canvas, col.toDouble(), row.toDouble(),
        dotW, dotH, dotSize, Color.fromARGB(255, r, g, b));
  }
}

// ── Content implementations ───────────────────────────────────────────────────

/// RGB565 frame bytes → LED dots.  Used by Media Upload.
class Rgb565LedContent implements LedMatrixContent {
  final List<int> bytes;
  const Rgb565LedContent({required this.bytes});

  @override
  void paint(Canvas canvas, Size size, double dotSize) {
    final dotW = size.width  / kLedCols;
    final dotH = size.height / kLedRows;
    for (int row = 0; row < kLedRows; row++) {
      drawLedRowFromRgb565(canvas, bytes, row, dotW, dotH, dotSize);
    }
  }
}

/// Empty placeholder before image is loaded.  Used by Media Upload.
class EmptyLedContent implements LedMatrixContent {
  final Color color;
  const EmptyLedContent({required this.color});

  @override
  void paint(Canvas canvas, Size size, double dotSize) {
    final p = TextPainter(
      text: TextSpan(
        text: 'NO DATA',
        style: TextStyle(
          color: color.withValues(alpha: 0.2),
          fontSize: size.height * 0.22,
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, Offset(
      (size.width  - p.width)  / 2,
      (size.height - p.height) / 2,
    ));
  }
}

/// Clock face.  Used by Clock screen.
class ClockLedContent implements LedMatrixContent {
  final String timeString;
  final String? dateString;
  final String? amPm;
  final Color color;

  const ClockLedContent({
    required this.timeString,
    this.dateString,
    this.amPm,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size, double dotSize) {
    final hasDate = dateString != null && dateString!.isNotEmpty;
    final topY    = hasDate ? size.height * 0.08 : size.height * 0.15;

    final timeP = TextPainter(
      text: TextSpan(
        text: timeString,
        style: TextStyle(
          color: color,
          fontSize: size.height * (hasDate ? 0.40 : 0.50),
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: size.width * 0.008,
          shadows: [Shadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: size.height * 0.15,
          )],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    timeP.paint(canvas, Offset((size.width - timeP.width) / 2, topY));

    if (amPm != null) {
      final p = TextPainter(
        text: TextSpan(
          text: amPm,
          style: TextStyle(
            color: color.withValues(alpha: 0.55),
            fontSize: size.height * 0.15,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(
        (size.width - p.width) / 2,
        topY + timeP.height + size.height * 0.02,
      ));
    }

    if (hasDate) {
      final lineY = size.height * 0.72;
      canvas.drawLine(
        Offset(size.width * 0.2, lineY),
        Offset(size.width * 0.8, lineY),
        Paint()..color = color.withValues(alpha: 0.2)..strokeWidth = 0.8,
      );
      final p = TextPainter(
        text: TextSpan(
          text: dateString,
          style: TextStyle(
            color: color.withValues(alpha: 0.5),
            fontSize: size.height * 0.15,
            fontFamily: 'monospace',
            letterSpacing: size.width * 0.005,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(
        (size.width - p.width) / 2,
        lineY + size.height * 0.04,
      ));
    }
  }
}

/// Spotify now-playing layout.  Used by Spotify screen.
class SpotifyLedContent implements LedMatrixContent {
  final String title;
  final String artist;
  final bool showArtist;
  final double trackProgress;
  final bool showProgress;
  final SpotifyLedLayout layout;
  final Color spotifyColor;

  const SpotifyLedContent({
    required this.title,
    required this.artist,
    required this.showArtist,
    required this.trackProgress,
    required this.showProgress,
    required this.layout,
    required this.spotifyColor,
  });

  @override
  void paint(Canvas canvas, Size size, double dotSize) {
    switch (layout) {
      case SpotifyLedLayout.artOnly:
        _paintArtOnly(canvas, size);
      case SpotifyLedLayout.textOnly:
      case SpotifyLedLayout.scrollingText:
        _paintText(canvas, size, leftPad: size.width * 0.04);
      case SpotifyLedLayout.artAndText:
        _paintArtAndText(canvas, size);
    }
    if (showProgress) _paintProgressBar(canvas, size);
  }

  void _paintArtOnly(Canvas canvas, Size size) {
    final sq   = size.height * 0.78;
    final left = (size.width  - sq) / 2;
    final top  = (size.height - sq) / 2 -
        (showProgress ? size.height * 0.06 : 0);
    final tile = sq / 8;
    for (int ty = 0; ty < 8; ty++) {
      for (int tx = 0; tx < 8; tx++) {
        canvas.drawRect(
          Rect.fromLTWH(left + tx * tile, top + ty * tile, tile, tile),
          Paint()..color = spotifyColor.withValues(
              alpha: (tx + ty) % 2 == 0 ? 0.35 : 0.18),
        );
      }
    }
    canvas.drawCircle(
      Offset(left + sq / 2, top + sq / 2),
      sq * 0.1,
      Paint()..color = spotifyColor,
    );
  }

  void _paintArtAndText(Canvas canvas, Size size) {
    final artW = size.width * 0.30;
    final tile = artW / 4;
    for (int ty = 0; ty < 4; ty++) {
      for (int tx = 0; tx < 4; tx++) {
        canvas.drawRect(
          Rect.fromLTWH(tx * tile, ty * (size.height / 4), tile, size.height / 4),
          Paint()..color = spotifyColor.withValues(
              alpha: (tx + ty) % 2 == 0 ? 0.28 : 0.14),
        );
      }
    }
    canvas.drawLine(
      Offset(artW + 2, size.height * 0.1),
      Offset(artW + 2,
          showProgress ? size.height * 0.78 : size.height * 0.9),
      Paint()..color = spotifyColor.withValues(alpha: 0.2)..strokeWidth = 1,
    );
    _paintText(canvas, size,
        leftPad: artW + size.width * 0.04, rightPad: size.width * 0.03);
  }

  void _paintText(Canvas canvas, Size size,
      {double leftPad = 0, double rightPad = 0}) {
    final availW   = size.width - leftPad - rightPad;
    final titleTop = showArtist ? size.height * 0.10 : size.height * 0.25;

    final titleP = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: spotifyColor,
          fontSize: size.height * 0.26,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          shadows: [Shadow(
            color: spotifyColor.withValues(alpha: 0.5),
            blurRadius: size.height * 0.12,
          )],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1, ellipsis: '…',
    )..layout(maxWidth: availW);
    titleP.paint(canvas, Offset(leftPad, titleTop));

    if (showArtist) {
      final artistP = TextPainter(
        text: TextSpan(
          text: artist,
          style: TextStyle(
            color: spotifyColor.withValues(alpha: 0.55),
            fontSize: size.height * 0.18,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1, ellipsis: '…',
      )..layout(maxWidth: availW);
      artistP.paint(
        canvas,
        Offset(leftPad, titleTop + titleP.height + size.height * 0.04),
      );
    }
  }

  void _paintProgressBar(Canvas canvas, Size size) {
    final barTop = size.height * 0.84;
    final barH   = size.height * 0.07;
    final barL   = size.width  * 0.04;
    final barW   = size.width  * 0.92;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(barL, barTop, barW, barH),
          Radius.circular(barH / 2)),
      Paint()..color = spotifyColor.withValues(alpha: 0.15),
    );
    if (trackProgress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(barL, barTop,
                barW * trackProgress.clamp(0.0, 1.0), barH),
            Radius.circular(barH / 2)),
        Paint()..color = spotifyColor,
      );
    }
  }
}

enum SpotifyLedLayout { artOnly, textOnly, artAndText, scrollingText }