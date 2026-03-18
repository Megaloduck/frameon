import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/device_api_service.dart';
import '../services/web_serial_service.dart';
import '../services/spotify_service.dart';
import '../models/device_state.dart';

// ── Core services ──────────────────────────────────────────────────────────

final deviceApiServiceProvider = ChangeNotifierProvider<DeviceApiService>(
  (ref) => DeviceApiService(),
);

final webSerialServiceProvider = ChangeNotifierProvider<WebSerialService>(
  (ref) => WebSerialService(),
);

// ── Derived device state ───────────────────────────────────────────────────

final deviceStateProvider = Provider<DeviceState>((ref) {
  return ref.watch(deviceApiServiceProvider).deviceState;
});

final connectionStatusProvider = Provider<ConnectionStatus>((ref) {
  return ref.watch(deviceStateProvider).connectionStatus;
});

final activeModeProvider = Provider<AppMode>((ref) {
  return ref.watch(deviceStateProvider).activeMode;
});

// ── Feature providers are defined in their own files ──────────────────────
// clockConfigProvider       → lib/screens/clock/clock_screen.dart
// pomodoroConfigProvider    → lib/screens/pomodoro/pomodoro_screen.dart
// pomodoroTimerProvider     → lib/screens/pomodoro/pomodoro_screen.dart
// gifListProvider           → lib/screens/gif/gif_screen.dart
// spotifyServiceProvider    → lib/services/spotify_service.dart
