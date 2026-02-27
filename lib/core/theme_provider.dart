import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Theme notifier ────────────────────────────────────────────────────────────

class ThemeNotifier extends Notifier<ThemeMode> {
  static const _prefKey = 'frameon_theme_mode';

  @override
  ThemeMode build() {
    // Kick off async load. State starts as dark; _load() will correct it
    // on the next frame if the user previously saved light mode.
    //
    // To eliminate the flash entirely, call ThemeNotifier.preload() before
    // runApp() and pass the result to ProviderScope overrides:
    //
    //   final saved = await ThemeNotifier.preload();
    //   runApp(ProviderScope(
    //     overrides: [themeProvider.overrideWith(() => ThemeNotifier()
    //         ..state = saved)],
    //     child: FrameonApp(),
    //   ));
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      state = _fromString(raw);
    }
  }

  /// Call this before [runApp] to read the saved theme synchronously-ish,
  /// avoiding the dark-mode flash on startup.
  static Future<ThemeMode> preload() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromString(prefs.getString(_prefKey));
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    // Persist first so we never store a value that doesn't match the UI.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(next));
    state = next;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      // system is not surfaced in the UI; treat as a no-op to avoid
      // storing a value we can't round-trip.
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(mode));
    state = mode;
  }

  bool get isDark => state == ThemeMode.dark;

  // ── Serialisation helpers ─────────────────────────────────────

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'light':  return ThemeMode.light;
      case 'dark':   return ThemeMode.dark;
      default:       return ThemeMode.dark; // safe fallback
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:  return 'light';
      case ThemeMode.dark:   return 'dark';
      case ThemeMode.system: return 'dark'; // never reached via setMode
    }
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);

// ── Convenience extensions ────────────────────────────────────────────────────

extension ThemeModeX on ThemeMode {
  bool get isDark => this == ThemeMode.dark;
  String get label => isDark ? 'DARK' : 'LIGHT';
  IconData get icon => isDark ? Icons.dark_mode : Icons.light_mode;
}