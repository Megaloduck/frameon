import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble_uuids.dart';
import 'package:frameon/features/frame_encoder/frame_model.dart';
import 'ble_manager.dart';

// ── Transfer state ────────────────────────────────────────────────────────────

enum TransferState { idle, sending, success, error }

class TransferProgress {
  final TransferState state;
  final int bytesSent;
  final int totalBytes;
  final int currentFrame;
  final int totalFrames;
  final String? error;

  const TransferProgress({
    required this.state,
    this.bytesSent = 0,
    this.totalBytes = 0,
    this.currentFrame = 0,
    this.totalFrames = 1,
    this.error,
  });

  double get progress =>
      totalBytes > 0 ? (bytesSent / totalBytes).clamp(0.0, 1.0) : 0;

  static const idle = TransferProgress(state: TransferState.idle);
}

// ── BLE Service ───────────────────────────────────────────────────────────────

/// Handles all data transmission to the ESP32 over BLE.
/// Requires a connected [BleManager] instance.
///
/// Usage:
/// ```dart
/// final service = BleService(manager: bleManager);
/// await service.sendFrame(sequence);
/// ```
class BleService {
  final BleManager _manager;
  final _progressCtrl = StreamController<TransferProgress>.broadcast();

  Stream<TransferProgress> get progressStream => _progressCtrl.stream;
  TransferProgress _progress = TransferProgress.idle;
  TransferProgress get progress => _progress;

  StreamSubscription? _statusSub;

  BleService({required BleManager manager}) : _manager = manager;

  // ── Public API ────────────────────────────────────────────────

  /// Send a full [FrameSequence] to the device.
  /// Handles both still frames and multi-frame GIFs.
  Future<void> sendSequence(FrameSequence sequence) async {
    final deviceId = _assertConnected();

    if (sequence.isAnimated) {
      await _sendGifMeta(deviceId, sequence);
    }

    final totalBytes = sequence.frames.fold<int>(
        0, (sum, f) => sum + f.byteCount);

    _emitProgress(TransferProgress(
      state: TransferState.sending,
      totalBytes: totalBytes,
      totalFrames: sequence.frameCount,
    ));

    int bytesSent = 0;
    for (int i = 0; i < sequence.frameCount; i++) {
      await _sendSingleFrame(
        deviceId,
        sequence.frames[i],
        frameIndex: i,
        totalFrames: sequence.frameCount,
        onBytesSent: (n) {
          bytesSent += n;
          _emitProgress(TransferProgress(
            state: TransferState.sending,
            bytesSent: bytesSent,
            totalBytes: totalBytes,
            currentFrame: i,
            totalFrames: sequence.frameCount,
          ));
        },
      );
    }

    _emitProgress(TransferProgress(
      state: TransferState.success,
      bytesSent: totalBytes,
      totalBytes: totalBytes,
      totalFrames: sequence.frameCount,
    ));
  }

  /// Send a raw control command byte (+ optional payload).
  Future<void> sendCommand(int command, [List<int> payload = const []]) async {
    final deviceId = _assertConnected();
    final char = _manager.controlCharacteristic(deviceId);
    await _manager.ble.writeCharacteristicWithResponse(
      char,
      value: [command, ...payload],
    );
  }

  /// Clear the matrix display.
  Future<void> clearDisplay() => sendCommand(kCmdClear);

  /// Set brightness 0–255.
  Future<void> setBrightness(int value) =>
      sendCommand(kCmdSetBrightness, [value.clamp(0, 255)]);

  /// Set display mode.
  Future<void> setMode(int mode) => sendCommand(kCmdSetMode, [mode]);

  /// Sync RTC on ESP32 with current device time.
  Future<void> syncClock({
    required bool is24h,
    required bool showSeconds,
    required bool showDate,
  }) async {
    final deviceId = _assertConnected();
    final char = _manager.clockConfigCharacteristic(deviceId);

    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final flags = (is24h ? 0x01 : 0x00) |
        (showSeconds ? 0x02 : 0x00) |
        (showDate ? 0x04 : 0x00);

    // Payload: [epoch u32 big-endian (4 bytes), flags (1 byte)]
    final data = ByteData(5);
    data.setUint32(0, epoch, Endian.big);
    data.setUint8(4, flags);

    await _manager.ble.writeCharacteristicWithResponse(
      char,
      value: data.buffer.asUint8List(),
    );
  }

  /// Ping the device — returns true if ack received within timeout.
  Future<bool> ping() async {
    final deviceId = _assertConnected();
    final ack = Completer<bool>();

    final sub = _manager.ble
        .subscribeToCharacteristic(_manager.statusCharacteristic(deviceId))
        .listen((data) {
      if (data.isNotEmpty && data[0] == kCmdPing) {
        if (!ack.isCompleted) ack.complete(true);
      }
    });

    await sendCommand(kCmdPing);

    final result = await ack.future
        .timeout(kAckTimeout, onTimeout: () => false);

    await sub.cancel();
    return result;
  }

  // ── Frame transmission ────────────────────────────────────────

  Future<void> _sendSingleFrame(
    String deviceId,
    FrameData frame, {
    required int frameIndex,
    required int totalFrames,
    required void Function(int) onBytesSent,
  }) async {
    final controlChar = _manager.controlCharacteristic(deviceId);
    final frameChar = _manager.frameDataCharacteristic(deviceId);

    // 1. Signal start
    await _manager.ble.writeCharacteristicWithResponse(
      controlChar,
      value: [kCmdFrameBegin, frameIndex, totalFrames],
    );

    // 2. Send data in chunks
    final bytes = Uint8List.fromList(frame.bytes);
    final chunkSize = _manager.chunkSize;
    int offset = 0;

    while (offset < bytes.length) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);

      // Use writeWithoutResponse for speed; ESP32 should buffer
      await _manager.ble.writeCharacteristicWithoutResponse(
        frameChar,
        value: chunk,
      );

      onBytesSent(chunk.length);
      offset = end;

      // Small delay to prevent buffer overflow on ESP32
      if (offset < bytes.length) {
        await Future.delayed(kChunkDelay);
      }
    }

    // 3. Commit — wait for ack
    await _waitForAck(deviceId, () async {
      await _manager.ble.writeCharacteristicWithResponse(
        controlChar,
        value: [kCmdFrameCommit],
      );
    });
  }

  Future<void> _sendGifMeta(String deviceId, FrameSequence sequence) async {
    final char = _manager.gifMetaCharacteristic(deviceId);

    // Payload: [frameCount u8, ...durations u16 big-endian]
    final data = ByteData(1 + sequence.frameCount * 2);
    data.setUint8(0, sequence.frameCount);
    for (int i = 0; i < sequence.frameCount; i++) {
      data.setUint16(1 + i * 2,
          sequence.frames[i].durationMs.clamp(0, 65535), Endian.big);
    }

    await _manager.ble.writeCharacteristicWithResponse(
      char,
      value: data.buffer.asUint8List(),
    );
  }

  // ── Ack handling ──────────────────────────────────────────────

  Future<void> _waitForAck(
      String deviceId, Future<void> Function() sendFn) async {
    final ack = Completer<void>();

    final sub = _manager.ble
        .subscribeToCharacteristic(_manager.statusCharacteristic(deviceId))
        .listen((data) {
      if (data.isNotEmpty && data[0] == kStatusOk) {
        if (!ack.isCompleted) ack.complete();
      } else if (data.isNotEmpty && data[0] == kStatusError) {
        if (!ack.isCompleted) {
          ack.completeError('ESP32 returned error status');
        }
      }
    });

    await sendFn();

    try {
      await ack.future.timeout(kAckTimeout);
    } on TimeoutException {
      // Proceed anyway — don't block the whole transfer on a missed ack
    } finally {
      await sub.cancel();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _assertConnected() {
    final id = _manager.connectedDeviceId;
    if (id == null) throw StateError('Not connected to a device');
    return id;
  }

  void _emitProgress(TransferProgress p) {
    _progress = p;
    _progressCtrl.add(p);
  }

  void dispose() {
    _statusSub?.cancel();
    _progressCtrl.close();
  }
}