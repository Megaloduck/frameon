import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_uuids.dart';

// ── Connection state ──────────────────────────────────────────────────────────

enum FrameonConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class FrameonDevice {
  final String id;
  final String name;
  final int rssi;

  const FrameonDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

// ── BLE Manager ───────────────────────────────────────────────────────────────

/// Manages BLE lifecycle: permissions, scanning, connecting, reconnecting.
///
/// Usage:
/// ```dart
/// final ble = BleManager();
/// await ble.requestPermissions();
/// ble.startScan();
/// ble.connectionStateStream.listen(print);
/// ble.connect(device);
/// ```
class BleManager {
  final _ble = FlutterReactiveBle();

  // ── State streams ─────────────────────────────────────────────

  final _connectionStateCtrl =
      StreamController<FrameonConnectionState>.broadcast();
  Stream<FrameonConnectionState> get connectionStateStream =>
      _connectionStateCtrl.stream;

  final _devicesCtrl = StreamController<List<FrameonDevice>>.broadcast();
  Stream<List<FrameonDevice>> get devicesStream => _devicesCtrl.stream;

  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorCtrl.stream;

  // ── Internal state ────────────────────────────────────────────

  FrameonConnectionState _state = FrameonConnectionState.disconnected;
  FrameonConnectionState get state => _state;

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;

  StreamSubscription? _scanSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _bleStatusSub;

  final List<FrameonDevice> _foundDevices = [];

  int _negotiatedMtu = kDefaultChunkSize + 3;
  int get chunkSize => _negotiatedMtu - 3;

  // ── Permissions ───────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((s) => s.isGranted);
  }

  // ── Scanning ──────────────────────────────────────────────────

  void startScan({Duration timeout = const Duration(seconds: 15)}) {
    if (_state == FrameonConnectionState.scanning) return;

    _foundDevices.clear();
    _devicesCtrl.add([]);
    _setState(FrameonConnectionState.scanning);

    _scanSub?.cancel();
    _scanSub = _ble.scanForDevices(
      withServices: [Uuid.parse(kFrameonServiceUuid)],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) {
        final fd = FrameonDevice(
          id: device.id,
          name: device.name.isEmpty ? 'Unknown' : device.name,
          rssi: device.rssi,
        );

        final idx = _foundDevices.indexWhere((d) => d.id == fd.id);
        if (idx >= 0) {
          _foundDevices[idx] = fd;
        } else {
          _foundDevices.add(fd);
        }
        _devicesCtrl.add(List.from(_foundDevices));
      },
      onError: (e) {
        _emitError('Scan error: $e');
        _setState(FrameonConnectionState.disconnected);
      },
    );

    // Auto-stop after timeout
    Future.delayed(timeout, () {
      if (_state == FrameonConnectionState.scanning) stopScan();
    });
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    if (_state == FrameonConnectionState.scanning) {
      _setState(FrameonConnectionState.disconnected);
    }
  }

  // ── Connect ───────────────────────────────────────────────────

  Future<void> connect(FrameonDevice device) async {
    stopScan();
    _setState(FrameonConnectionState.connecting);

    _connectionSub?.cancel();
    _connectionSub = _ble
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: {
            Uuid.parse(kFrameonServiceUuid): [
              Uuid.parse(kFrameDataUuid),
              Uuid.parse(kControlUuid),
              Uuid.parse(kStatusUuid),
              Uuid.parse(kClockConfigUuid),
              Uuid.parse(kGifMetaUuid),
            ],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) async {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _connectedDeviceId = device.id;
                await _negotiateMtu(device.id);
                _setState(FrameonConnectionState.connected);
                break;
              case DeviceConnectionState.disconnected:
                _connectedDeviceId = null;
                _setState(FrameonConnectionState.disconnected);
                break;
              case DeviceConnectionState.connecting:
                _setState(FrameonConnectionState.connecting);
                break;
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (e) {
            _emitError('Connection error: $e');
            _connectedDeviceId = null;
            _setState(FrameonConnectionState.error);
          },
        );
  }

  Future<void> disconnect() async {
    _connectionSub?.cancel();
    _connectionSub = null;
    _connectedDeviceId = null;
    _setState(FrameonConnectionState.disconnected);
  }

  // ── MTU negotiation ───────────────────────────────────────────

  Future<void> _negotiateMtu(String deviceId) async {
    try {
      final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 247);
      _negotiatedMtu = mtu;
    } catch (_) {
      // Fall back to safe default
      _negotiatedMtu = kDefaultChunkSize + 3;
    }
  }

  // ── Characteristic accessors (used by BleService) ─────────────

  QualifiedCharacteristic frameDataCharacteristic(String deviceId) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(kFrameonServiceUuid),
        characteristicId: Uuid.parse(kFrameDataUuid),
        deviceId: deviceId,
      );

  QualifiedCharacteristic controlCharacteristic(String deviceId) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(kFrameonServiceUuid),
        characteristicId: Uuid.parse(kControlUuid),
        deviceId: deviceId,
      );

  QualifiedCharacteristic statusCharacteristic(String deviceId) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(kFrameonServiceUuid),
        characteristicId: Uuid.parse(kStatusUuid),
        deviceId: deviceId,
      );

  QualifiedCharacteristic clockConfigCharacteristic(String deviceId) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(kFrameonServiceUuid),
        characteristicId: Uuid.parse(kClockConfigUuid),
        deviceId: deviceId,
      );

  QualifiedCharacteristic gifMetaCharacteristic(String deviceId) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(kFrameonServiceUuid),
        characteristicId: Uuid.parse(kGifMetaUuid),
        deviceId: deviceId,
      );

  FlutterReactiveBle get ble => _ble;

  // ── Helpers ───────────────────────────────────────────────────

  void _setState(FrameonConnectionState s) {
    _state = s;
    _connectionStateCtrl.add(s);
  }

  void _emitError(String msg) => _errorCtrl.add(msg);

  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _bleStatusSub?.cancel();
    _connectionStateCtrl.close();
    _devicesCtrl.close();
    _errorCtrl.close();
  }
}