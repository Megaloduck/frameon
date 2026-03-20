import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'web_serial_service.dart';

/// USB serial command/response transport for ESP32.
///
/// Send:  {"id":"<hex6>","cmd":"<name>","data":{...}}\n
/// Recv:  {"id":"<hex6>","ok":true,"data":{...}}\n
///     or {"id":"<hex6>","ok":false,"error":"..."}\n
/// Push:  {"push":"<event>","data":{...}}\n  (ESP32-initiated)
///
/// Subscribes directly to [WebSerialService.lineStream] — no log polling,
/// no missed lines, no race conditions between connect and first command.
class UsbApiService extends ChangeNotifier {
  final WebSerialService _serial;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final _pushCtrl = StreamController<UsbPushEvent>.broadcast();
  Stream<UsbPushEvent> get pushEvents => _pushCtrl.stream;

  StreamSubscription<String>? _lineSub;

  static const _defaultTimeout = Duration(seconds: 8);
  static const _chunkTimeout   = Duration(seconds: 20);

  UsbApiService(this._serial) {
    _serial.addListener(_onSerialStatus);
    if (_serial.status == WebSerialStatus.connected) _subscribeToLines();
  }

  bool get isConnected => _serial.status == WebSerialStatus.connected;

  // ── Commands ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> ping() => _cmd('ping');
  Future<Map<String, dynamic>> getStatus() => _cmd('status');

  Future<void> setMode(String mode) =>
      _cmd('set_mode', data: {'mode': mode});

  Future<void> setBrightness(int value) =>
      _cmd('set_brightness', data: {'value': value});

  Future<void> setClockConfig({
    bool? is24h, bool? showDate, bool? showSeconds,
    String? timezone, String? ntp, int? brightness,
  }) => _cmd('clock_config', data: {
        if (is24h != null)       'format24h':   is24h,
        if (showDate != null)    'showDate':    showDate,
        if (showSeconds != null) 'showSeconds': showSeconds,
        if (timezone != null)    'timezone':    timezone,
        if (ntp != null)         'ntp':         ntp,
        if (brightness != null)  'brightness':  brightness,
      });

  Future<void> setPomoConfig({
    int? workMinutes, int? shortBreakMinutes,
    int? longBreakMinutes, int? sessionsBeforeLong,
  }) => _cmd('pomo_config', data: {
        if (workMinutes != null)        'work':        workMinutes,
        if (shortBreakMinutes != null)  'shortBreak':  shortBreakMinutes,
        if (longBreakMinutes != null)   'longBreak':   longBreakMinutes,
        if (sessionsBeforeLong != null) 'sessions':    sessionsBeforeLong,
      });

  Future<void> pomoCommand(String cmd) =>
      _cmd('pomo_cmd', data: {'cmd': cmd});

  Future<void> setSpotifyState({
    required String track, required String artist,
    required bool isPlaying, String? artBase64,
  }) => _cmd('spotify_state', data: {
        'track': track, 'artist': artist, 'playing': isPlaying,
        if (artBase64 != null) 'art': artBase64,
      });

  Future<Map<String, dynamic>> getGifList() => _cmd('gif_list');

  Future<void> selectGif(String filename) =>
      _cmd('gif_select', data: {'file': filename});

  Future<void> deleteGif(String filename) =>
      _cmd('gif_delete', data: {'file': filename});

  /// Upload a GIF in 4KB base64 chunks with optional progress callback.
  Future<void> uploadGif(
    Uint8List bytes, String filename, {
    ValueChanged<double>? onProgress,
  }) async {
    const chunkSize = 4096;
    final totalChunks = (bytes.length / chunkSize).ceil();
    await _cmd('gif_start', data: {
      'filename': filename,
      'totalBytes': bytes.length,
      'chunks': totalChunks,
    });
    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end   = min(start + chunkSize, bytes.length);
      await _cmd('gif_chunk', data: {
        'index': i,
        'data':  base64Encode(bytes.sublist(start, end)),
        'final': i == totalChunks - 1,
      }, timeout: _chunkTimeout);
      onProgress?.call((i + 1) / totalChunks);
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _cmd(
    String cmd, {
    Map<String, dynamic>? data,
    Duration timeout = _defaultTimeout,
  }) async {
    if (!isConnected) throw UsbApiException('USB port not open');

    final id      = _newId();
    final payload = jsonEncode({
      'id': id, 'cmd': cmd,
      if (data != null && data.isNotEmpty) 'data': data,
    });

    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    try {
      await _serial.rawSend('$payload\n');
    } catch (e) {
      _pending.remove(id);
      throw UsbApiException('Send failed: $e');
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw UsbApiException(
          'Command "$cmd" timed out after ${timeout.inSeconds}s — '
          'verify usb_api_loop() is running in firmware loop()');
    }
  }

  void _onLine(String line) {
    // Ignore legacy provisioning lines and ESP32 debug prints starting with '['
    if (line.startsWith('IP:') || line.startsWith('ERR:') || line.startsWith('[')) return;

    Map<String, dynamic> msg;
    try { msg = jsonDecode(line) as Map<String, dynamic>; }
    catch (_) { return; }

    // ESP32-initiated push event
    if (msg.containsKey('push')) {
      _pushCtrl.add(UsbPushEvent(
        type: msg['push'] as String? ?? '',
        data: msg['data'] as Map<String, dynamic>? ?? {},
      ));
      return;
    }

    // Response to a pending command — match by id
    final id = msg['id'] as String?;
    if (id == null) return;
    final c = _pending.remove(id);
    if (c == null || c.isCompleted) return;

    if (msg['ok'] == true) {
      final raw = msg['data'];
      if (raw is String) {
        try { c.complete(jsonDecode(raw) as Map<String, dynamic>); }
        catch (_) { c.complete({'raw': raw}); }
      } else if (raw is Map<String, dynamic>) {
        c.complete(raw);
      } else {
        c.complete({});
      }
    } else {
      c.completeError(UsbApiException(msg['error'] as String? ?? 'unknown error'));
    }
  }

  void _subscribeToLines() {
    _lineSub?.cancel();
    _lineSub = _serial.lineStream.listen(
      _onLine,
      onError: (_) {/* non-fatal */},
      onDone: () { _failAll('USB port closed'); _lineSub = null; },
    );
    debugPrint('[UsbApi] Subscribed to line stream');
  }

  void _onSerialStatus() {
    if (_serial.status == WebSerialStatus.connected) {
      _subscribeToLines();
      notifyListeners();
    } else if (_serial.status != WebSerialStatus.connected) {
      _lineSub?.cancel();
      _lineSub = null;
      _failAll('USB disconnected');
      notifyListeners();
    }
  }

  void _failAll(String reason) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(UsbApiException(reason));
    }
    _pending.clear();
  }

  static final _rng = Random.secure();
  static String _newId() {
    return List.generate(6, (_) => _rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void dispose() {
    _serial.removeListener(_onSerialStatus);
    _lineSub?.cancel();
    _pushCtrl.close();
    super.dispose();
  }
}

class UsbPushEvent {
  final String type;
  final Map<String, dynamic> data;
  const UsbPushEvent({required this.type, required this.data});
}

class UsbApiException implements Exception {
  final String message;
  const UsbApiException(this.message);
  @override String toString() => 'UsbApiException: $message';
}
