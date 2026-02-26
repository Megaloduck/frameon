import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ble_manager.dart';
import 'ble_service.dart';

/// Single BleManager instance for the whole app lifetime.
final bleManagerProvider = Provider<BleManager>((ref) {
  final manager = BleManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// Single BleService instance wired to the shared BleManager.
final bleServiceProvider = Provider<BleService>((ref) {
  final manager = ref.watch(bleManagerProvider);
  final service = BleService(manager: manager);
  ref.onDispose(service.dispose);
  return service;
});

/// Live connection state — rebuild widgets when BLE state changes.
final bleConnectionStateProvider =
    StreamProvider<FrameonConnectionState>((ref) {
  final manager = ref.watch(bleManagerProvider);
  return manager.connectionStateStream;
});

/// Live device list during scanning.
final bleDeviceListProvider =
    StreamProvider<List<FrameonDevice>>((ref) {
  final manager = ref.watch(bleManagerProvider);
  return manager.devicesStream;
});