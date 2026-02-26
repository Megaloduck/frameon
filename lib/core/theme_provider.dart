import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Theme notifier ────────────────────────────────────────────────────────────

class ThemeNotifier extends Notifier<ThemeMode> {
  static const _prefKey = 'frameon_theme_mode';

  @override
  ThemeMode build() {
    // Load persisted value asynchronously; start with system default (dark)
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefKey);
    if (value != null) {
      state = value == 'light' ? ThemeMode.light : ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, state == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode == ThemeMode.light ? 'light' : 'dark');
  }

  bool get isDark => state == ThemeMode.dark;
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