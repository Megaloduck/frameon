import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'usb_api_service.dart';
import 'device_api_service.dart';
import '../models/device_state.dart';

enum ActiveTransport { none, usb, wifi }

/// Unified command layer.
/// USB is always preferred when the serial port is open.
/// Falls back to WiFi automatically on USB disconnect.
/// All feature screens call this instead of talking to USB or WiFi directly.
class TransportService extends ChangeNotifier {
  final UsbApiService    _usb;
  final DeviceApiService _wifi;

  ActiveTransport _transport = ActiveTransport.none;
  String? _lastError;
  double  _gifUploadProgress = 0;
  bool    _isUploading       = false;

  ActiveTransport get transport           => _transport;
  String?         get lastError           => _lastError;
  double          get gifUploadProgress   => _gifUploadProgress;
  bool            get isUploading         => _isUploading;
  bool            get isConnected         => _transport != ActiveTransport.none;

  String get transportLabel => switch (_transport) {
    ActiveTransport.usb  => 'USB',
    ActiveTransport.wifi => 'Wi-Fi',
    ActiveTransport.none => 'None',
  };

  TransportService(this._usb, this._wifi) {
    _usb.addListener(_onUsbChange);
    _wifi.addListener(_onWifiChange);
    _onUsbChange(); // set initial state
  }

  // ── Transport selection — USB wins ─────────────────────────────────────

  void _onUsbChange() {
    if (_usb.isConnected && _transport != ActiveTransport.usb) {
      _transport = ActiveTransport.usb;
      debugPrint('[Transport] → USB');
      notifyListeners();
    } else if (!_usb.isConnected && _transport == ActiveTransport.usb) {
      // USB lost — fall back to WiFi if connected, otherwise none
      _transport = _wifi.deviceState.isConnected
          ? ActiveTransport.wifi
          : ActiveTransport.none;
      debugPrint('[Transport] USB lost → ${_transport.name}');
      notifyListeners();
    }
  }

  void _onWifiChange() {
    if (_transport == ActiveTransport.usb) return; // USB wins, ignore WiFi changes
    final next = _wifi.deviceState.isConnected
        ? ActiveTransport.wifi
        : ActiveTransport.none;
    if (next != _transport) {
      _transport = next;
      debugPrint('[Transport] → ${_transport.name}');
      notifyListeners();
    }
  }

  // ── Unified API ───────────────────────────────────────────────────────

  Future<bool> setMode(AppMode mode) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.setMode(mode.name);
    } else {
      await _wifi.setMode(mode);
    }
  });

  Future<bool> setBrightness(int value) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.setBrightness(value);
    } else {
      await _wifi.setBrightness(value);
    }
  });

  Future<bool> setClockConfig({
    bool? is24h, bool? showDate, bool? showSeconds,
    String? timezone, String? ntp, int? brightness,
  }) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.setClockConfig(
        is24h: is24h, showDate: showDate, showSeconds: showSeconds,
        timezone: timezone, ntp: ntp, brightness: brightness,
      );
    } else {
      await _wifi.postJson('/api/clock/config', {
        if (is24h != null)       'format24h':   is24h,
        if (showDate != null)    'showDate':    showDate,
        if (showSeconds != null) 'showSeconds': showSeconds,
        if (timezone != null)    'timezone':    timezone,
        if (ntp != null)         'ntp':         ntp,
        if (brightness != null)  'brightness':  brightness,
      });
    }
  });

  Future<bool> setPomoConfig({
    int? workMinutes, int? shortBreakMinutes,
    int? longBreakMinutes, int? sessionsBeforeLong,
  }) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.setPomoConfig(
        workMinutes: workMinutes, shortBreakMinutes: shortBreakMinutes,
        longBreakMinutes: longBreakMinutes, sessionsBeforeLong: sessionsBeforeLong,
      );
    } else {
      await _wifi.postJson('/api/pomodoro/config', {
        if (workMinutes != null)        'work':       workMinutes,
        if (shortBreakMinutes != null)  'shortBreak': shortBreakMinutes,
        if (longBreakMinutes != null)   'longBreak':  longBreakMinutes,
        if (sessionsBeforeLong != null) 'sessions':   sessionsBeforeLong,
      });
    }
  });

  Future<bool> pomoCommand(String cmd) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.pomoCommand(cmd);
    } else {
      await _wifi.pomodoroCommand(cmd);
    }
  });

  Future<bool> pushSpotifyState({
    required String track, required String artist,
    required bool isPlaying, Uint8List? albumArtJpeg,
  }) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.setSpotifyState(
        track: track, artist: artist, isPlaying: isPlaying,
        artBase64: albumArtJpeg != null ? base64Encode(albumArtJpeg) : null,
      );
    } else {
      await _wifi.pushSpotifyState(
        trackName: track, artistName: artist,
        isPlaying: isPlaying, albumArtJpeg: albumArtJpeg,
      );
    }
  });

  /// USB: chunked base64, progress per chunk.
  /// WiFi: caller must use uploadGifFile() extension directly.
  Future<bool> uploadGifUsb(
    Uint8List bytes, String filename, {
    ValueChanged<double>? onProgress,
  }) => _run(() async {
    if (_transport != ActiveTransport.usb) {
      throw UsbApiException('USB not connected — use WiFi upload path');
    }
    _isUploading = true; _gifUploadProgress = 0; notifyListeners();
    try {
      await _usb.uploadGif(bytes, filename, onProgress: (p) {
        _gifUploadProgress = p; onProgress?.call(p); notifyListeners();
      });
    } finally {
      _isUploading = false; notifyListeners();
    }
  });

  Future<List<Map<String, dynamic>>> listGifs() async {
    _lastError = null;
    try {
      if (_transport == ActiveTransport.usb) {
        final r = await _usb.getGifList();
        return (r['files'] as List? ?? []).cast<Map<String, dynamic>>();
      } else {
        final r = await _wifi.getJson('/api/gif/list');
        return (r?['files'] as List? ?? []).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      _lastError = e.toString();
      return [];
    }
  }

  Future<bool> selectGif(String filename) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.selectGif(filename);
    } else {
      await _wifi.selectGif(filename);
    }
  });

  Future<bool> deleteGif(String filename) => _run(() async {
    if (_transport == ActiveTransport.usb) {
      await _usb.deleteGif(filename);
    } else {
      await _wifi.postJson('/api/gif/delete', {'file': filename});
    }
  });

  // ── Helper ────────────────────────────────────────────────────────────

  Future<bool> _run(Future<void> Function() fn) async {
    _lastError = null;
    if (!isConnected) {
      _lastError = 'No device connected (USB or WiFi)';
      return false;
    }
    try {
      await fn();
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[Transport] error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _usb.removeListener(_onUsbChange);
    _wifi.removeListener(_onWifiChange);
    super.dispose();
  }
}
