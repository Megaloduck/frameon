import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'frame_model.dart';

/// Target matrix dimensions.
const int kMatrixCols = 64;
const int kMatrixRows = 32;
const int kMatrixPixels = kMatrixCols * kMatrixRows;
const int kFrameBytes = kMatrixPixels * 2; // 2 bytes per pixel (RGB565)

/// Encodes image data into RGB565 format for the ESP32 LED matrix.
class Rgb565Encoder {
  final bool useDithering;
  final double brightness; // 0.0 – 1.0

  /// When true, convert to grayscale before encoding.
  /// Uses ITU-R BT.709 luma: Y = 0.2126R + 0.7152G + 0.0722B
  /// so green-heavy images don't over-brighten.
  final bool grayscale;

  const Rgb565Encoder({
    this.useDithering = true,
    this.brightness = 1.0,
    this.grayscale = false,
  });

  // ── Public API ────────────────────────────────────────────────────────────

  /// Encode a single [img.Image] frame into a [FrameData].
  FrameData encodeFrame(img.Image frame, {int durationMs = 0}) {
    final resized = _ensureSize(frame);
    final bytes = useDithering
        ? _encodeWithDithering(resized)
        : _encodeRaw(resized);
    return FrameData(bytes: bytes, durationMs: durationMs);
  }

  /// Encode all frames of an [img.Image] (handles GIF animations).
  ///
  /// [frameDurationOverride] — when non-null every frame uses this fixed
  /// duration (ms) regardless of what's baked into the GIF.
  ///
  /// [frameDurationMultiplier] — scales each frame's original duration.
  /// 1.0 = unchanged, 0.5 = 2× faster, 2.0 = 2× slower.
  /// Ignored when [frameDurationOverride] is set.
  FrameSequence encodeSequence(
    img.Image image, {
    int? frameDurationOverride,
    double frameDurationMultiplier = 1.0,
  }) {
    if (image.numFrames <= 1) {
      return FrameSequence.still(encodeFrame(image));
    }

    final frames = <FrameData>[];
    for (int i = 0; i < image.numFrames; i++) {
      final frame = image.frames[i];
      // GIF frameDuration is in centiseconds → convert to ms
      final originalMs = (frame.frameDuration * 10).round().clamp(16, 5000);
      final int durationMs;
      if (frameDurationOverride != null) {
        durationMs = frameDurationOverride.clamp(16, 5000);
      } else {
        durationMs =
            (originalMs * frameDurationMultiplier).round().clamp(16, 5000);
      }
      frames.add(encodeFrame(frame, durationMs: durationMs));
    }
    return FrameSequence.animated(frames);
  }

  /// Encode raw RGBA bytes (e.g. from Flutter's toByteData) into a [FrameData].
  FrameData encodeRgba(List<int> rgba, int width, int height) {
    final Uint8List bytes =
        rgba is Uint8List ? rgba : Uint8List.fromList(rgba);
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      format: img.Format.uint8,
      numChannels: 4,
    );
    return encodeFrame(image);
  }

  // ── Resize ────────────────────────────────────────────────────────────────

  img.Image _ensureSize(img.Image src) {
    if (src.width == kMatrixCols && src.height == kMatrixRows) return src;
    return img.copyResize(
      src,
      width: kMatrixCols,
      height: kMatrixRows,
      interpolation: img.Interpolation.average,
    );
  }

  // ── Grayscale ─────────────────────────────────────────────────────────────

  /// ITU-R BT.709 luma.  Returns (y, y, y).
  (int, int, int) _toGray(int r, int g, int b) {
    final y = (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
    return (y, y, y);
  }

  // ── Encoding: raw ─────────────────────────────────────────────────────────

  List<int> _encodeRaw(img.Image image) {
    final bytes = <int>[];
    for (int y = 0; y < kMatrixRows; y++) {
      for (int x = 0; x < kMatrixCols; x++) {
        final pixel = image.getPixel(x, y);
        var r = _applyBrightness(pixel.r.toInt());
        var g = _applyBrightness(pixel.g.toInt());
        var b = _applyBrightness(pixel.b.toInt());
        if (grayscale) (r, g, b) = _toGray(r, g, b);
        final word = _toRgb565(r, g, b);
        bytes.add((word >> 8) & 0xFF);
        bytes.add(word & 0xFF);
      }
    }
    return bytes;
  }

  // ── Encoding: Floyd-Steinberg dithering ───────────────────────────────────

  List<int> _encodeWithDithering(img.Image image) {
    // Pre-compute brightness + grayscale for all three channels up front.
    double _ch(img.Pixel p, int ch) {
      final rv = _applyBrightness(p.r.toInt()).toDouble();
      final gv = _applyBrightness(p.g.toInt()).toDouble();
      final bv = _applyBrightness(p.b.toInt()).toDouble();
      if (grayscale) {
        return 0.2126 * rv + 0.7152 * gv + 0.0722 * bv;
      }
      return ch == 0 ? rv : ch == 1 ? gv : bv;
    }

    final r = List<double>.generate(
        kMatrixPixels,
        (i) => _ch(image.getPixel(i % kMatrixCols, i ~/ kMatrixCols), 0));
    final g = List<double>.generate(
        kMatrixPixels,
        (i) => _ch(image.getPixel(i % kMatrixCols, i ~/ kMatrixCols), 1));
    final b = List<double>.generate(
        kMatrixPixels,
        (i) => _ch(image.getPixel(i % kMatrixCols, i ~/ kMatrixCols), 2));

    final bytes = <int>[];

    for (int y = 0; y < kMatrixRows; y++) {
      for (int x = 0; x < kMatrixCols; x++) {
        final idx = y * kMatrixCols + x;

        final qr = _quantise8to5(r[idx].round().clamp(0, 255));
        final qg = _quantise8to6(g[idx].round().clamp(0, 255));
        final qb = _quantise8to5(b[idx].round().clamp(0, 255));

        final out8r = _expand5to8(qr);
        final out8g = _expand6to8(qg);
        final out8b = _expand5to8(qb);

        final word = _toRgb565Raw(qr, qg, qb);
        bytes.add((word >> 8) & 0xFF);
        bytes.add(word & 0xFF);

        final er = r[idx] - out8r;
        final eg = g[idx] - out8g;
        final eb = b[idx] - out8b;

        _distributeError(r, x + 1, y,     er * 7 / 16);
        _distributeError(r, x - 1, y + 1, er * 3 / 16);
        _distributeError(r, x,     y + 1, er * 5 / 16);
        _distributeError(r, x + 1, y + 1, er * 1 / 16);

        _distributeError(g, x + 1, y,     eg * 7 / 16);
        _distributeError(g, x - 1, y + 1, eg * 3 / 16);
        _distributeError(g, x,     y + 1, eg * 5 / 16);
        _distributeError(g, x + 1, y + 1, eg * 1 / 16);

        _distributeError(b, x + 1, y,     eb * 7 / 16);
        _distributeError(b, x - 1, y + 1, eb * 3 / 16);
        _distributeError(b, x,     y + 1, eb * 5 / 16);
        _distributeError(b, x + 1, y + 1, eb * 1 / 16);
      }
    }
    return bytes;
  }

  void _distributeError(List<double> channel, int x, int y, double error) {
    if (x < 0 || x >= kMatrixCols || y < 0 || y >= kMatrixRows) return;
    channel[y * kMatrixCols + x] += error;
  }

  // ── Conversion helpers ────────────────────────────────────────────────────

  int _applyBrightness(int value) =>
      (value * brightness).round().clamp(0, 255);

  int _toRgb565(int r, int g, int b) {
    return _toRgb565Raw(_quantise8to5(r), _quantise8to6(g), _quantise8to5(b));
  }

  int _toRgb565Raw(int r5, int g6, int b5) => (r5 << 11) | (g6 << 5) | b5;

  int _quantise8to5(int v) => (v >> 3) & 0x1F;
  int _quantise8to6(int v) => (v >> 2) & 0x3F;
  int _expand5to8(int v)   => (v << 3) | (v >> 2);
  int _expand6to8(int v)   => (v << 2) | (v >> 4);
}