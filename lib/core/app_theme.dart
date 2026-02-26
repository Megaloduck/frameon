import 'package:flutter/material.dart';

// ── App color tokens ──────────────────────────────────────────────────────────
//
// Instead of hardcoding hex everywhere, screens read colours from
// [AppColors.of(context)] which resolves correctly for both themes.

class AppColors {
  final Color background;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;       // neon green / primary brand
  final Color accentBlue;   // cyan
  final Color accentYellow;
  final Color accentRed;
  final Color accentSpotify;
  final Color headerBg;
  final Color inputBg;
  final Color toggleActive;
  final Color toggleInactive;
  final bool isDark;

  const AppColors({
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentBlue,
    required this.accentYellow,
    required this.accentRed,
    required this.accentSpotify,
    required this.headerBg,
    required this.inputBg,
    required this.toggleActive,
    required this.toggleInactive,
    required this.isDark,
  });

  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? _dark : _light;
  }

  // ── Dark theme (original terminal aesthetic) ──────────────────

  static const _dark = AppColors(
    isDark: true,
    background:     Color(0xFF0A0A0F),
    surface:        Color(0xFF0D0D1A),
    border:         Color(0xFF1A1A2E),
    textPrimary:    Color(0xFFFFFFFF),
    textSecondary:  Color(0xFFAAAAAA),
    textMuted:      Color(0xFF444444),
    accent:         Color(0xFF00FF41),
    accentBlue:     Color(0xFF00B4FF),
    accentYellow:   Color(0xFFFFE600),
    accentRed:      Color(0xFFFF2D2D),
    accentSpotify:  Color(0xFF1DB954),
    headerBg:       Color(0xFF0D0D1A),
    inputBg:        Color(0xFF111122),
    toggleActive:   Color(0xFF00FF41),
    toggleInactive: Color(0xFF1A1A2E),
  );

  // ── Light theme (clean, modern, high contrast) ────────────────

  static const _light = AppColors(
    isDark: false,
    background:     Color(0xFFF2F4F7),
    surface:        Color(0xFFFFFFFF),
    border:         Color(0xFFDDE1EA),
    textPrimary:    Color(0xFF0F1117),
    textSecondary:  Color(0xFF4A5568),
    textMuted:      Color(0xFFADB5BD),
    accent:         Color(0xFF00B341),   // slightly deeper green for contrast on white
    accentBlue:     Color(0xFF0099DD),
    accentYellow:   Color(0xFFD4A800),
    accentRed:      Color(0xFFE02020),
    accentSpotify:  Color(0xFF1AA34A),
    headerBg:       Color(0xFFFFFFFF),
    inputBg:        Color(0xFFF8F9FB),
    toggleActive:   Color(0xFF00B341),
    toggleInactive: Color(0xFFDDE1EA),
  );
}

// ── ThemeData factories ───────────────────────────────────────────────────────

class AppTheme {
  static ThemeData dark() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors._dark.background,
    fontFamily: 'monospace',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors._dark.accent,
      brightness: Brightness.dark,
      surface: AppColors._dark.surface,
    ),
    dividerColor: AppColors._dark.border,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors._dark.surface,
      contentTextStyle: const TextStyle(
        color: Colors.white, fontFamily: 'monospace', fontSize: 12,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors._dark.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: Color(0xFF1A1A2E)),
      ),
    ),
  );

  static ThemeData light() => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors._light.background,
    fontFamily: 'monospace',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors._light.accent,
      brightness: Brightness.light,
      surface: AppColors._light.surface,
    ),
    dividerColor: AppColors._light.border,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors._light.surface,
      contentTextStyle: TextStyle(
        color: AppColors._light.textPrimary,
        fontFamily: 'monospace', fontSize: 12,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors._light.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: Color(0xFFDDE1EA)),
      ),
    ),
  );
}