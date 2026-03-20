import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('serialBridge.isAvailable')  external bool          _jsIsAvailable();
@JS('serialBridge.requestPort')  external JSPromise<JSBoolean> _jsRequestPort();
@JS('serialBridge.openPort')     external JSPromise<JSAny?> _jsOpenPort(int baud);
@JS('serialBridge.write')        external JSPromise<JSAny?> _jsWrite(JSString data);
@JS('serialBridge.close')        external JSPromise<JSAny?> _jsClose();
@JS('serialBridge.addLineListener')    external void _jsAddLineListener(JSFunction cb);
@JS('serialBridge.removeLineListener') external void _jsRemoveLineListener(JSFunction cb);

enum WebSerialStatus { unavailable, idle, requestingPort, connecting, connected, error }

class WebSerialMessage {
  final String text;
  final bool isOutgoing;
  final DateTime timestamp;
  const WebSerialMessage({required this.text, required this.isOutgoing, required this.timestamp});
}

class WebSerialService extends ChangeNotifier {
  WebSerialStatus _status = WebSerialStatus.idle;
  final List<WebSerialMessage> _log = [];
  JSFunction? _jsListenerRef;

  // ── Broadcast stream ─────────────────────────────────────────────────
  // A new controller is created each time a port opens.
  // It is a BROADCAST stream — every subscriber (UsbApiService, requestDeviceIp)
  // receives every line simultaneously. No line is consumed by one subscriber
  // before another can see it.
  StreamController<String>? _lineCtrl;

  WebSerialStatus get status => _status;
  List<WebSerialMessage> get log => List.unmodifiable(_log);

  /// Broadcast stream of complete lines from ESP32.
  /// Subscribe at any time — each subscriber gets all future lines.
  Stream<String> get lineStream => _lineCtrl?.stream ?? const Stream.empty();

  bool get isAvailable {
    if (!kIsWeb) return false;
    try { return _jsIsAvailable(); } catch (_) { return false; }
  }

  Future<bool> requestPort() async {
    if (!isAvailable) { _status = WebSerialStatus.unavailable; notifyListeners(); return false; }
    _status = WebSerialStatus.requestingPort; notifyListeners();
    try {
      final granted = (await _jsRequestPort().toDart).toDart;
      if (!granted) { _status = WebSerialStatus.idle; notifyListeners(); return false; }
      _status = WebSerialStatus.connecting; notifyListeners();
      await _openPort();
      return true;
    } catch (e) {
      _status = WebSerialStatus.error;
      _addLog('Error: $e', isOutgoing: false);
      notifyListeners();
      return false;
    }
  }

  Future<void> sendWifiCredentials(String ssid, String password) async {
    final payload = '{"cmd":"wifi","ssid":"$ssid","password":"$password"}\n';
    await _send(payload);
    _addLog('→ Sent Wi-Fi credentials (SSID: $ssid)', isOutgoing: true);
  }

  /// Waits for a line starting with "IP:" on the broadcast stream.
  /// Because it's a broadcast, UsbApiService can be subscribed at the same time
  /// and both will independently receive every line — no collision.
  Future<String?> requestDeviceIp() async {
    await _send('{"cmd":"get_ip"}\n');
    _addLog('→ Requested device IP', isOutgoing: true);
    try {
      final response = await lineStream
          .firstWhere((l) => l.startsWith('IP:'))
          .timeout(const Duration(seconds: 20));
      final ip = response.replaceFirst('IP:', '').trim();
      _addLog('← Device IP: $ip', isOutgoing: false);
      return ip;
    } catch (_) {
      _addLog('✗ Timed out waiting for IP', isOutgoing: false);
      return null;
    }
  }

  Future<void> disconnect() async {
    _removeJsListener();
    await _closeStream();
    if (kIsWeb) { try { await _jsClose().toDart; } catch (_) {} }
    _status = WebSerialStatus.idle;
    notifyListeners();
  }

  /// Public raw send for UsbApiService.
  Future<void> rawSend(String data) => _send(data);

  Future<void> _openPort() async {
    await _closeStream();
    // IMPORTANT: create the broadcast controller BEFORE registering the JS listener
    // so no lines are lost between open and subscribe.
    _lineCtrl = StreamController<String>.broadcast();

    await _jsOpenPort(115200).toDart;

    _jsListenerRef = ((JSString jsLine) {
      final line = jsLine.toDart;
      // Push to broadcast stream first, then log.
      // ALL subscribers receive this simultaneously.
      final ctrl = _lineCtrl;
      if (ctrl != null && !ctrl.isClosed) ctrl.add(line);
      _addLog(line, isOutgoing: false);
    }).toJS;
    _jsAddLineListener(_jsListenerRef!);

    _status = WebSerialStatus.connected;
    _addLog('Port opened at 115200 baud', isOutgoing: false);
    notifyListeners();
  }

  Future<void> _closeStream() async {
    final ctrl = _lineCtrl;
    _lineCtrl = null;
    if (ctrl != null && !ctrl.isClosed) await ctrl.close();
  }

  Future<void> _send(String data) async {
    if (_status != WebSerialStatus.connected) throw StateError('Serial port not open');
    await _jsWrite(data.toJS).toDart;
  }

  void _removeJsListener() {
    if (_jsListenerRef != null) {
      try { _jsRemoveLineListener(_jsListenerRef!); } catch (_) {}
      _jsListenerRef = null;
    }
  }

  void _addLog(String text, {required bool isOutgoing}) {
    _log.add(WebSerialMessage(text: text, isOutgoing: isOutgoing, timestamp: DateTime.now()));
    if (_log.length > 300) _log.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() { disconnect(); super.dispose(); }
}
