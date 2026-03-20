import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'device_api_service.dart';
import 'web_serial_service.dart';
import 'usb_api_service.dart';
import 'transport_service.dart';
import 'spotify_service.dart';
import '../models/device_state.dart';

// ── Core services ──────────────────────────────────────────────────────────
// These are app-lifetime singletons — never disposed while the app runs.
// Using ChangeNotifierProvider (not autoDispose) ensures that.

final deviceApiServiceProvider = ChangeNotifierProvider<DeviceApiService>(
  (ref) => DeviceApiService(),
);

final webSerialServiceProvider = ChangeNotifierProvider<WebSerialService>(
  (ref) => WebSerialService(),
);

/// USB command API — wraps WebSerialService with request/response protocol.
/// Must NOT be autoDispose — it holds the line stream subscription.
final usbApiServiceProvider = ChangeNotifierProvider<UsbApiService>((ref) {
  // Watch so the provider stays alive as long as webSerial does.
  // Do NOT use ref.read here — we want dependency tracking.
  final serial = ref.watch(webSerialServiceProvider);
  final svc    = UsbApiService(serial);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Unified transport — USB preferred, WiFi fallback.
/// Must NOT be autoDispose — screens rebuild constantly and we must not
/// dispose the transport mid-session (causes "used after disposed" crash).
final transportProvider = ChangeNotifierProvider<TransportService>((ref) {
  final usb  = ref.watch(usbApiServiceProvider);
  final wifi = ref.watch(deviceApiServiceProvider);
  final svc  = TransportService(usb, wifi);
  ref.onDispose(svc.dispose);
  return svc;
});

// ── Derived state ──────────────────────────────────────────────────────────

final deviceStateProvider = Provider<DeviceState>((ref) {
  return ref.watch(deviceApiServiceProvider).deviceState;
});

final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  return ref.watch(deviceStateProvider).connectionStatus;
});

final activeModeProvider = Provider<AppMode>((ref) {
  return ref.watch(deviceStateProvider).activeMode;
});

/// Which transport is currently active.
final activeTransportProvider = Provider<ActiveTransport>((ref) {
  return ref.watch(transportProvider).transport;
});

// spotifyServiceProvider  → lib/services/spotify_service.dart
// clockConfigProvider     → lib/screens/clock/clock_screen.dart
// pomodoroConfigProvider  → lib/screens/pomodoro/pomodoro_screen.dart
// pomodoroTimerProvider   → lib/screens/pomodoro/pomodoro_screen.dart
// gifListProvider         → lib/screens/gif/gif_screen.dart
