import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'frame_model.dart';
import 'rgb565_encoder.dart';

/// High-level image pipeline: decode → transform → encode → [FrameSequence].
///
/// Construct once per user action with the desired settings, then call one
/// of the `process*` methods.  Every method is async so heavy work can be
/// offloaded to an isolate later without changing callers.
class ImageProcessor {
  final bool dithering;
  final double brightness; // 0.0 – 1.0
  final bool grayscale;    // ITU-R BT.709 luma conversion

  const ImageProcessor({
    this.dithering  = true,
    this.brightness = 1.0,
    this.grayscale  = false,
  });

  // ── Encoder factory ───────────────────────────────────────────────────────

  Rgb565Encoder _makeEncoder() => Rgb565Encoder(
    useDithering: dithering,
    brightness:   brightness,
    grayscale:    grayscale,
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Stretch the image to fill the full 64 × 32 matrix (may distort).
  Future<FrameSequence> processBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');
    return _makeEncoder().encodeSequence(image);
  }

  /// Scale the image to fit within 64 × 32, padding with black bars.
  Future<FrameSequence> processLetterboxed(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');
    final processed = _letterbox(image);
    return _makeEncoder().encodeSequence(processed);
  }

  /// Scale the image so its shorter side fills the matrix, then centre-crop.
  Future<FrameSequence> processCropped(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');
    final processed = _cropToMatrix(image);
    return _makeEncoder().encodeSequence(processed);
  }

  /// Decode an animated GIF and encode every frame, preserving per-frame
  /// timing from the GIF unless overridden by the caller.
  ///
  /// [frameDurationOverride] — when non-null every frame gets this fixed
  /// duration in milliseconds, ignoring whatever the GIF specifies.
  ///
  /// [frameDurationMultiplier] — scales each frame's original GIF duration.
  /// 1.0 = unchanged, 0.5 = 2× faster, 2.0 = 2× slower.
  /// Ignored when [frameDurationOverride] is set.
  Future<FrameSequence> processGif(
    Uint8List bytes, {
    int?   frameDurationOverride,
    double frameDurationMultiplier = 1.0,
  }) async {
    // decodeGif preserves per-frame timing; decodeImage is the fallback for
    // single-frame or malformed GIFs.
    final image = img.decodeGif(bytes) ?? img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode GIF');
    return _makeEncoder().encodeSequence(
      image,
      frameDurationOverride:   frameDurationOverride,
      frameDurationMultiplier: frameDurationMultiplier,
    );
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  /// Letterbox: fit the whole image inside 64 × 32 with black padding.
  img.Image _letterbox(img.Image src) {
    const targetW = 64;
    const targetH = 32;

    // Scale so the image fits entirely within the target rectangle.
    final scaleX = targetW / src.width;
    final scaleY = targetH / src.height;
    final scale  = scaleX < scaleY ? scaleX : scaleY;

    final scaledW = (src.width  * scale).round();
    final scaledH = (src.height * scale).round();

    final scaled = img.copyResize(
      src,
      width:  scaledW,
      height: scaledH,
      interpolation: img.Interpolation.average,
    );

    // Composite onto a black canvas.
    final canvas = img.Image(width: targetW, height: targetH);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

    final offsetX = (targetW - scaledW) ~/ 2;
    final offsetY = (targetH - scaledH) ~/ 2;

    img.compositeImage(canvas, scaled, dstX: offsetX, dstY: offsetY);
    return canvas;
  }

  /// Centre-crop: scale so the shorter side fills 64 × 32, then crop.
  img.Image _cropToMatrix(img.Image src) {
    const targetW = 64;
    const targetH = 32;

    // Scale so the image covers the full target (both dimensions >= target).
    final scaleX = targetW / src.width;
    final scaleY = targetH / src.height;
    final scale  = scaleX > scaleY ? scaleX : scaleY;

    final scaledW = (src.width  * scale).ceil();
    final scaledH = (src.height * scale).ceil();

    final scaled = img.copyResize(
      src,
      width:  scaledW,
      height: scaledH,
      interpolation: img.Interpolation.average,
    );

    // Crop to exact target size from the centre.
    final cropX = (scaledW - targetW) ~/ 2;
    final cropY = (scaledH - targetH) ~/ 2;

    return img.copyCrop(
      scaled,
      x: cropX,
      y: cropY,
      width:  targetW,
      height: targetH,
    );
  }
}