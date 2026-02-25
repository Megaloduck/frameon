/// A single rendered frame as RGB565 bytes, ready for BLE transmission.
class FrameData {
  /// Raw RGB565 bytes. Each pixel = 2 bytes, big-endian.
  /// Length is always kCols * kRows * 2 = 64 * 32 * 2 = 4096 bytes.
  final List<int> bytes;

  /// Display duration in milliseconds (relevant for GIF frames).
  final int durationMs;

  const FrameData({
    required this.bytes,
    this.durationMs = 0,
  });

  int get byteCount => bytes.length;
  int get pixelCount => bytes.length ~/ 2;
}

/// A sequence of frames — either a single still (length 1) or an animated GIF.
class FrameSequence {
  final List<FrameData> frames;
  final bool isAnimated;

  const FrameSequence({
    required this.frames,
    required this.isAnimated,
  });

  factory FrameSequence.still(FrameData frame) =>
      FrameSequence(frames: [frame], isAnimated: false);

  factory FrameSequence.animated(List<FrameData> frames) =>
      FrameSequence(frames: frames, isAnimated: true);

  int get frameCount => frames.length;

  /// Total loop duration in milliseconds.
  int get totalDurationMs =>
      frames.fold(0, (sum, f) => sum + f.durationMs);
}