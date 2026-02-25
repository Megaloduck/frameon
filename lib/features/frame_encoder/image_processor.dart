import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'rgb565_encoder.dart';
import 'frame_model.dart';

/// Supported source types for the image processor.
enum ImageSourceType { still, gif, albumArt }

/// High-level pipeline: load → decode → resize → encode → [FrameSequence].
///
/// Usage:
/// ```dart
/// final processor = ImageProcessor();
/// final sequence = await processor.processFile(File('art.gif'));
/// bleManager.sendSequence(sequence);
/// ```
class ImageProcessor {
  final Rgb565Encoder _encoder;

  ImageProcessor({
    bool dithering = true,
    double brightness = 1.0,
  }) : _encoder = Rgb565Encoder(
          useDithering: dithering,
          brightness: brightness,
        );

  // ── File pipeline ─────────────────────────────────────────────

  /// Load and process any supported image file (PNG, JPG, GIF, BMP, WebP).
  Future<FrameSequence> processFile(File file) async {
    final bytes = await file.readAsBytes();
    return processBytes(bytes);
  }

  /// Process raw image bytes (e.g. from file_picker or network).
  Future<FrameSequence> processBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');
    return _encoder.encodeSequence(image);
  }

  /// Process a GIF specifically, extracting all frames with timing.
  Future<FrameSequence> processGif(Uint8List bytes) async {
    final gif = img.decodeGif(bytes);
    if (gif == null) throw Exception('Failed to decode GIF');
    return _encoder.encodeSequence(gif);
  }

  // ── Album art pipeline ────────────────────────────────────────

  /// Process album art from a URL response body.
  /// Applies a slight contrast boost to look good on LED matrix.
  Future<FrameSequence> processAlbumArt(Uint8List bytes) async {
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode album art');

    // Resize to matrix dimensions first
    image = img.copyResize(
      image,
      width: kMatrixCols,
      height: kMatrixRows,
      interpolation: img.Interpolation.average,
    );

    // Boost saturation slightly so it pops on the LED matrix
    image = img.adjustColor(image, saturation: 1.2, contrast: 1.1);

    final frame = _encoder.encodeFrame(image);
    return FrameSequence.still(frame);
  }

  // ── Cropping helpers ──────────────────────────────────────────

  /// Crop to centre square before resizing (good for portrait album art).
  img.Image _cropToSquare(img.Image image) {
    final size = image.width < image.height ? image.width : image.height;
    final x = (image.width - size) ~/ 2;
    final y = (image.height - size) ~/ 2;
    return img.copyCrop(image, x: x, y: y, width: size, height: size);
  }

  /// Letterbox: fit image into 64×32 preserving aspect ratio, black bars.
  img.Image _letterbox(img.Image image) {
    final srcRatio = image.width / image.height;
    const dstRatio = kMatrixCols / kMatrixRows;

    int targetW, targetH;
    if (srcRatio > dstRatio) {
      targetW = kMatrixCols;
      targetH = (kMatrixCols / srcRatio).round();
    } else {
      targetH = kMatrixRows;
      targetW = (kMatrixRows * srcRatio).round();
    }

    final resized = img.copyResize(image, width: targetW, height: targetH);
    final canvas = img.Image(width: kMatrixCols, height: kMatrixRows);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

    final offsetX = (kMatrixCols - targetW) ~/ 2;
    final offsetY = (kMatrixRows - targetH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);
    return canvas;
  }

  /// Process with letterboxing (preserves aspect ratio).
  Future<FrameSequence> processLetterboxed(Uint8List bytes) async {
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');
    image = _letterbox(image);
    final frame = _encoder.encodeFrame(image);
    return FrameSequence.still(frame);
  }

  /// Process with centre-crop (fills full matrix, may clip edges).
  Future<FrameSequence> processCropped(Uint8List bytes) async {
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');
    image = _cropToSquare(image);
    image = img.copyResize(image, width: kMatrixCols, height: kMatrixRows);
    final frame = _encoder.encodeFrame(image);
    return FrameSequence.still(frame);
  }
}