import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

// ── JS interop bindings to window.serialBridge ───────────────────────────
// Matches the API exposed by web/serial_interops.js

@JS('serialBridge.isAvailable')
external bool _jsIsAvailable();

@JS('serialBridge.requestPort')
external JSPromise<JSBoolean> _jsRequestPort();

@JS('serialBridge.openPort')
external JSPromise<JSAny?> _jsOpenPort(int baudRate);

@JS('serialBridge.write')
external JSPromise<JSAny?> _jsWrite(JSString data);

@JS('serialBridge.close')
external JSPromise<JSAny?> _jsClose();

@JS('serialBridge.addLineListener')
external void _jsAddLineListener(JSFunction callback);

@JS('serialBridge.removeLineListener')
external void _jsRemoveLineListener(JSFunction callback);

// ── Enums & value types ───────────────────────────────────────────────────

enum WebSerialStatus {
  unavailable,
  idle,
  requestingPort,
  connecting,
  connected,
  error,
}

class WebSerialMessage {
  final String text;
  final bool isOutgoing;
  final DateTime timestamp;

  const WebSerialMessage({
    required this.text,
    required this.isOutgoing,
    required this.timestamp,
  });
}

// ── Service ───────────────────────────────────────────────────────────────

/// Abstracts Web Serial communication for ESP32 Wi-Fi provisioning.
/// On web: uses window.serialBridge (backed by Web Serial API in serial_interops.js).
/// On desktop/non-web: [isAvailable] returns false — user enters IP manually.
class WebSerialService extends ChangeNotifier {
  WebSerialStatus _status = WebSerialStatus.idle;
  final List<WebSerialMessage> _log = [];
  StreamController<String>? _lineController;
  Stream<String>? _lines;
  JSFunction? _jsListenerRef;

  WebSerialStatus get status => _status;
  List<WebSerialMessage> get log => List.unmodifiable(_log);

  bool get isAvailable {
    if (!kIsWeb) return false;
    try {
      return _jsIsAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPort() async {
    if (!isAvailable) {
      _status = WebSerialStatus.unavailable;
      notifyListeners();
      return false;
    }
    _status = WebSerialStatus.requestingPort;
    notifyListeners();
    try {
      final granted = (await _jsRequestPort().toDart).toDart;
      if (!granted) {
        _status = WebSerialStatus.idle;
        notifyListeners();
        return false;
      }
      _status = WebSerialStatus.connecting;
      notifyListeners();
      await _openPort();
      return true;
    } catch (e) {
      _status = WebSerialStatus.error;
      _addLog('Error opening port: $e', isOutgoing: false);
      notifyListeners();
      return false;
    }
  }

  Future<void> sendWifiCredentials(String ssid, String password) async {
    final payload = '{"cmd":"wifi","ssid":"$ssid","password":"$password"}\n';
    await _send(payload);
    _addLog('→ Sent Wi-Fi credentials (SSID: $ssid)', isOutgoing: true);
  }

  Future<String?> requestDeviceIp() async {
    await _send('{"cmd":"get_ip"}\n');
    _addLog('→ Requested device IP', isOutgoing: true);
    try {
      final response = await _lines!
          .firstWhere((l) => l.startsWith('IP:'))
          .timeout(const Duration(seconds: 20));
      final ip = response.replaceFirst('IP:', '').trim();
      _addLog('← Device IP: $ip', isOutgoing: false);
      return ip;
    } catch (_) {
      _addLog('✗ Timed out waiting for IP response', isOutgoing: false);
      return null;
    }
  }

  Future<void> disconnect() async {
    _removeJsListener();
    _lineController?.close();
    _lineController = null;
    _lines = null;
    if (kIsWeb) {
      try {
        await _jsClose().toDart;
      } catch (_) {}
    }
    _status = WebSerialStatus.idle;
    notifyListeners();
  }

  Future<void> _openPort() async {
    await _jsOpenPort(115200).toDart;
    _lineController = StreamController<String>.broadcast();
    _lines = _lineController!.stream;
    _jsListenerRef = ((JSString jsLine) {
      final line = jsLine.toDart;
      if (!(_lineController?.isClosed ?? true)) {
        _addLog(line, isOutgoing: false);
        _lineController?.add(line);
      }
    }).toJS;
    _jsAddLineListener(_jsListenerRef!);
    _status = WebSerialStatus.connected;
    _addLog('Port opened at 115200 baud', isOutgoing: false);
    notifyListeners();
  }

  Future<void> _send(String data) async {
    if (_status != WebSerialStatus.connected) {
      throw StateError('Serial port not open');
    }
    await _jsWrite(data.toJS).toDart;
  }

  void _removeJsListener() {
    if (_jsListenerRef != null) {
      try {
        _jsRemoveLineListener(_jsListenerRef!);
      } catch (_) {}
      _jsListenerRef = null;
    }
  }

  void _addLog(String text, {required bool isOutgoing}) {
    _log.add(WebSerialMessage(
      text: text,
      isOutgoing: isOutgoing,
      timestamp: DateTime.now(),
    ));
    if (_log.length > 300) _log.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
