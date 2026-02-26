import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import '../frame_encoder/frame_model.dart';
import '../frame_encoder/image_processor.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/ble_uuids.dart';
import '../ui/connection_status.dart';
import '../ui/theme_switcher.dart';

enum ResizeMode { stretch, letterbox, crop }

class MediaUploadScreen extends ConsumerStatefulWidget {
  const MediaUploadScreen({super.key});

  @override
  ConsumerState<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends ConsumerState<MediaUploadScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _rawBytes;
  String? _fileName;
  bool _isGif = false;
  FrameSequence? _sequence;
  bool _processing = false;
  bool _isSending = false;
  double _transferProgress = 0.0;
  String? _error;

  ResizeMode _resizeMode = ResizeMode.letterbox;
  double _brightness = 1.0;
  bool _dithering = true;

  // GIF preview animation
  int _previewFrame = 0;
  late final AnimationController _gifController;

  @override
  void initState() {
    super.initState();
    _gifController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_advanceGifFrame);
  }

  @override
  void dispose() {
    _gifController.dispose();
    super.dispose();
  }

  void _advanceGifFrame() {
    if (_sequence == null || !_sequence!.isAnimated) return;
    final totalMs = _sequence!.totalDurationMs;
    if (totalMs == 0) return;
    final elapsed = (_gifController.value * totalMs).round();
    int acc = 0;
    for (int i = 0; i < _sequence!.frameCount; i++) {
      acc += _sequence!.frames[i].durationMs;
      if (elapsed < acc) {
        if (_previewFrame != i) setState(() => _previewFrame = i);
        break;
      }
    }
  }

  // ── File picking ──────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() {
      _rawBytes = bytes;
      _fileName = file.name;
      _isGif = file.extension?.toLowerCase() == 'gif';
      _sequence = null;
      _error = null;
      _previewFrame = 0;
    });

    await _processImage();
  }

  Future<void> _processImage() async {
    if (_rawBytes == null) return;
    setState(() { _processing = true; _error = null; });

    try {
      final processor = ImageProcessor(
        dithering: _dithering,
        brightness: _brightness,
      );

      FrameSequence sequence;
      switch (_resizeMode) {
        case ResizeMode.letterbox:
          sequence = await processor.processLetterboxed(_rawBytes!);
          break;
        case ResizeMode.crop:
          sequence = await processor.processCropped(_rawBytes!);
          break;
        case ResizeMode.stretch:
          sequence = await processor.processBytes(_rawBytes!);
          break;
      }

      // If it's a GIF, re-run with full GIF pipeline to preserve frames
      if (_isGif) {
        sequence = await processor.processGif(_rawBytes!);
      }

      setState(() { _sequence = sequence; _processing = false; });

      if (sequence.isAnimated && sequence.totalDurationMs > 0) {
        _gifController.duration =
            Duration(milliseconds: sequence.totalDurationMs);
        _gifController.repeat();
      } else {
        _gifController.stop();
      }
    } catch (e) {
      setState(() { _error = e.toString(); _processing = false; });
    }
  }

  Future<void> _sendToDevice() async {
    if (_sequence == null) return;
    final bleService = ref.read(bleServiceProvider);
    final bleManager = ref.read(bleManagerProvider);

    if (bleManager.state != FrameonConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No device connected. Tap the status bar to connect.',
            style: TextStyle(fontFamily: 'monospace')),
        backgroundColor: Color(0xFF1A0A0A),
      ));
      return;
    }

    setState(() { _isSending = true; _transferProgress = 0; });

    final sub = bleService.progressStream.listen((p) {
      if (mounted) setState(() => _transferProgress = p.progress);
    });

    try {
      await bleService.setMode(
          _sequence!.isAnimated ? kModeGif : kModePixelArt);
      await bleService.sendSequence(_sequence!);

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
    } finally {
      await sub.cancel();
      if (mounted) setState(() { _isSending = false; _transferProgress = 0; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bleManager = ref.watch(bleManagerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Column(
        children: [
          _buildHeader(),
          ConnectionStatusBar(
            manager: bleManager,
            onTap: () => DeviceScannerSheet.show(context, bleManager),
          ),
          if (_isSending)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: TransferProgressBar(
                progress: _transferProgress,
                label: 'TRANSMITTING FRAME DATA',
                color: const Color(0xFF00B4FF),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildMainPanel()),
                _buildRightPanel(),
              ],
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios,
                color: Color(0xFF444444), size: 16),
          ),
          const SizedBox(width: 16),
          const Text('MEDIA UPLOAD', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold,
            letterSpacing: 2, color: Colors.white, fontFamily: 'monospace',
          )),
          const SizedBox(width: 10),
          const Text('GIF · PNG · JPG', style: TextStyle(
            fontSize: 11, color: Color(0xFF444444),
            letterSpacing: 1.5, fontFamily: 'monospace',
          )),
          const Spacer(),
          if (_sequence != null)
            _HeaderBadge(
              label: _sequence!.isAnimated
                  ? '${_sequence!.frameCount} FRAMES'
                  : 'STILL',
              color: _sequence!.isAnimated
                  ? const Color(0xFFFFE600)
                  : const Color(0xFF00FF41),
            ),
          const SizedBox(width: 8),
          const ThemeToggleButton(),
        ],
      ),
    );
  }

  Widget _buildMainPanel() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Expanded(child: _buildDropZone()),
          const SizedBox(height: 24),
          _buildMatrixPreview(),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    if (_rawBytes != null && !_processing) {
      return _buildImagePreview();
    }

    return GestureDetector(
      onTap: _pickFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00FF41).withValues(alpha: 0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFF00FF41).withValues(alpha: 0.02),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_processing) ...[
                const SizedBox(
                  width: 32, height: 32,
                  child: CircularProgressIndicator(
                    color: Color(0xFF00FF41), strokeWidth: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('ENCODING...', style: TextStyle(
                  fontSize: 11, color: Color(0xFF00FF41),
                  letterSpacing: 2, fontFamily: 'monospace',
                )),
              ] else if (_error != null) ...[
                const Icon(Icons.error_outline,
                    color: Color(0xFFFF2D2D), size: 32),
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(
                  fontSize: 10, color: Color(0xFFFF2D2D),
                  fontFamily: 'monospace',
                ), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                _SmallButton(label: 'TRY AGAIN', onTap: _pickFile),
              ] else ...[
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF1A2A1A)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.upload_outlined,
                      color: Color(0xFF333333), size: 28),
                ),
                const SizedBox(height: 20),
                const Text('TAP TO UPLOAD', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold,
                  color: Color(0xFF00FF41), letterSpacing: 2,
                  fontFamily: 'monospace',
                )),
                const SizedBox(height: 8),
                const Text('PNG · JPG · GIF · BMP · WebP',
                  style: TextStyle(fontSize: 10, color: Color(0xFF333333),
                    letterSpacing: 1, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('Will be encoded to 64 × 32 RGB565',
                  style: TextStyle(fontSize: 10, color: Color(0xFF222222),
                    letterSpacing: 0.5, fontFamily: 'monospace')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1A2A1A)),
            borderRadius: BorderRadius.circular(8),
            color: Colors.black,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.memory(_rawBytes!, fit: BoxFit.contain),
          ),
        ),
        Positioned(
          top: 12, right: 12,
          child: GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A).withValues(alpha: 0.9),
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('CHANGE', style: TextStyle(
                fontSize: 9, color: Color(0xFF888888),
                letterSpacing: 1, fontFamily: 'monospace',
              )),
            ),
          ),
        ),
        if (_fileName != null)
          Positioned(
            bottom: 12, left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A).withValues(alpha: 0.9),
                border: Border.all(color: const Color(0xFF1A1A2E)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_fileName!, style: const TextStyle(
                fontSize: 9, color: Color(0xFF555555),
                letterSpacing: 0.5, fontFamily: 'monospace',
              )),
            ),
          ),
      ],
    );
  }

  // Matrix LED preview
  Widget _buildMatrixPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const _SectionLabel('MATRIX PREVIEW'),
          const SizedBox(width: 8),
          const Text('64 × 32', style: TextStyle(
            fontSize: 9, color: Color(0xFF333333), fontFamily: 'monospace',
          )),
          const Spacer(),
          if (_sequence != null && _sequence!.isAnimated)
            Text('FRAME ${_previewFrame + 1}/${_sequence!.frameCount}',
              style: const TextStyle(fontSize: 9, color: Color(0xFF444444),
                fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 8),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: const Color(0xFF1A2A1A)),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(
              color: const Color(0xFF00FF41).withValues(alpha: 0.04),
              blurRadius: 20,
            )],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: _sequence != null
                ? _MatrixPreviewPainter(
                    frame: _sequence!.frames[_previewFrame],
                  )
                : const Center(
                    child: Text('NO DATA', style: TextStyle(
                      fontSize: 9, color: Color(0xFF222222),
                      fontFamily: 'monospace',
                    )),
                  ),
          ),
        ),
      ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('RESIZE MODE'),
            const SizedBox(height: 10),
            ..._buildResizeModes(),
            const SizedBox(height: 20),
            const _SectionLabel('BRIGHTNESS'),
            const SizedBox(height: 8),
            _buildBrightnessSlider(),
            const SizedBox(height: 20),
            const _SectionLabel('OPTIONS'),
            const SizedBox(height: 10),
            _buildDitheringToggle(),
            const SizedBox(height: 24),
            if (_sequence != null) ...[
              const _SectionLabel('OUTPUT'),
              const SizedBox(height: 8),
              _InfoRow('Frames', '${_sequence!.frameCount}'),
              _InfoRow('Bytes', '${_sequence!.frames.first.byteCount * _sequence!.frameCount}'),
              if (_sequence!.isAnimated)
                _InfoRow('Duration', '${_sequence!.totalDurationMs}ms'),
              const SizedBox(height: 20),
            ],
            _ActionButton(
              label: _isSending ? 'SENDING...' : 'SEND TO DEVICE',
              color: const Color(0xFF00B4FF),
              enabled: _sequence != null && !_isSending,
              onTap: _sendToDevice,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'RE-ENCODE',
              color: const Color(0xFF00FF41),
              enabled: _rawBytes != null,
              onTap: _processImage,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResizeModes() {
    const modes = [
      (ResizeMode.letterbox, 'LETTERBOX', 'Preserve ratio, black bars'),
      (ResizeMode.crop,      'CROP',      'Fill matrix, centre crop'),
      (ResizeMode.stretch,   'STRETCH',   'Fill matrix, may distort'),
    ];
    return modes.map((m) {
      final active = _resizeMode == m.$1;
      return GestureDetector(
        onTap: () {
          setState(() => _resizeMode = m.$1);
          if (_rawBytes != null) _processImage();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00FF4115) : Colors.transparent,
            border: Border.all(
              color: active ? const Color(0xFF00FF41) : const Color(0xFF222222),
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? const Color(0xFF00FF41) : const Color(0xFF333333),
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.$2, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                color: active ? const Color(0xFF00FF41) : const Color(0xFF555555),
                letterSpacing: 1, fontFamily: 'monospace',
              )),
              Text(m.$3, style: const TextStyle(
                fontSize: 9, color: Color(0xFF333333), fontFamily: 'monospace',
              )),
            ]),
          ]),
        ),
      );
    }).toList();
  }

  Widget _buildBrightnessSlider() {
    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFF00FF41),
          inactiveTrackColor: const Color(0xFF1A1A2E),
          thumbColor: const Color(0xFF00FF41),
          overlayColor: const Color(0xFF00FF4122),
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: _brightness,
          min: 0.1,
          max: 1.0,
          onChanged: (v) => setState(() => _brightness = v),
          onChangeEnd: (_) { if (_rawBytes != null) _processImage(); },
        ),
      ),
      Text('${(_brightness * 100).round()}%', style: const TextStyle(
        fontSize: 10, color: Color(0xFF444444), fontFamily: 'monospace',
      )),
    ]);
  }

  Widget _buildDitheringToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _dithering = !_dithering);
        if (_rawBytes != null) _processImage();
      },
      child: Row(children: [
        Container(
          width: 32, height: 18,
          decoration: BoxDecoration(
            color: _dithering
                ? const Color(0xFF00FF4122)
                : const Color(0xFF1A1A2E),
            border: Border.all(
              color: _dithering ? const Color(0xFF00FF41) : const Color(0xFF333333),
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: _dithering ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: _dithering ? const Color(0xFF00FF41) : const Color(0xFF333333),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text('DITHERING', style: TextStyle(
          fontSize: 10, color: Color(0xFF555555),
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ]),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('MODE', _resizeMode.name.toUpperCase(), const Color(0xFF00FF41)),
        const SizedBox(width: 24),
        _StatusItem('BRIGHTNESS', '${(_brightness * 100).round()}%', const Color(0xFF666666)),
        const SizedBox(width: 24),
        _StatusItem('DITHER', _dithering ? 'ON' : 'OFF',
            _dithering ? const Color(0xFF00FF41) : const Color(0xFF444444)),
        const Spacer(),
        if (_sequence != null)
          Text(
            _sequence!.isAnimated
                ? 'ANIMATED GIF · ${_sequence!.frameCount} frames · ${_sequence!.totalDurationMs}ms'
                : 'STILL IMAGE · ${_sequence!.frames.first.byteCount} bytes',
            style: const TextStyle(fontSize: 9, color: Color(0xFF333333),
                fontFamily: 'monospace'),
          ),
      ]),
    );
  }
}

// ── Matrix preview widget ─────────────────────────────────────────────────────

class _MatrixPreviewPainter extends StatelessWidget {
  final FrameData frame;
  const _MatrixPreviewPainter({required this.frame});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePainter(frame: frame),
      size: Size.infinite,
    );
  }
}

class _FramePainter extends CustomPainter {
  final FrameData frame;
  const _FramePainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black);
    final pw = size.width / 64;
    final ph = size.height / 32;
    final bytes = frame.bytes;
    for (int i = 0; i < 64 * 32; i++) {
      if (i * 2 + 1 >= bytes.length) break;
      final word = (bytes[i * 2] << 8) | bytes[i * 2 + 1];
      final r = ((word >> 11) & 0x1F) << 3;
      final g = ((word >> 5) & 0x3F) << 2;
      final b = (word & 0x1F) << 3;
      if (r == 0 && g == 0 && b == 0) continue;
      final col = i % 64;
      final row = i ~/ 64;
      canvas.drawRect(
        Rect.fromLTWH(col * pw, row * ph, pw, ph),
        Paint()..color = Color.fromARGB(255, r, g, b),
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    fontSize: 9, letterSpacing: 2, color: Color(0xFF333333),
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF444444), fontFamily: 'monospace')),
        Text(value, style: const TextStyle(fontSize: 10, color: Color(0xFF888888), fontFamily: 'monospace')),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.color, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Opacity(
      opacity: enabled ? 1.0 : 0.3,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold, color: color,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
      ),
    ),
  );
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(
        fontSize: 10, color: Color(0xFF666666), fontFamily: 'monospace',
      )),
    ),
  );
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _HeaderBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label, style: TextStyle(
      fontSize: 9, color: color, letterSpacing: 1.5, fontFamily: 'monospace',
    )),
  );
}

class _StatusItem extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _StatusItem(this.label, this.value, this.valueColor);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: const TextStyle(
      fontSize: 10, color: Color(0xFF333333), fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor, fontFamily: 'monospace',
    )),
  ]);
}