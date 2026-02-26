import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme_provider.dart';
import '../../core/app_theme.dart';

// ── Compact toggle for screen headers ─────────────────────────────────────────

/// A small icon button that flips between dark/light mode.
/// Drop this anywhere in a Row (header toolbar, etc.)
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: () => ref.read(themeProvider.notifier).toggle(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            mode.icon,
            size: 13,
            color: mode.isDark ? colors.accent : colors.accentYellow,
          ),
          const SizedBox(width: 5),
          Text(
            mode.label,
            style: TextStyle(
              fontSize: 9,
              color: colors.textSecondary,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Full pill switcher for home screen ────────────────────────────────────────

/// Segmented pill control: DARK | LIGHT
class ThemeSwitcherPill extends ConsumerWidget {
  const ThemeSwitcherPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    final colors = AppColors.of(context);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Segment(
          icon: Icons.dark_mode,
          label: 'DARK',
          selected: mode.isDark,
          selectedColor: colors.accent,
          colors: colors,
          onTap: () => ref.read(themeProvider.notifier).setMode(ThemeMode.dark),
        ),
        Container(width: 1, color: colors.border),
        _Segment(
          icon: Icons.light_mode,
          label: 'LIGHT',
          selected: !mode.isDark,
          selectedColor: colors.accentYellow,
          colors: colors,
          onTap: () => ref.read(themeProvider.notifier).setMode(ThemeMode.light),
        ),
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final AppColors colors;
  final VoidCallback onTap;

  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: colors.isDark ? 0.12 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
              color: selected ? selectedColor : colors.textMuted),
          const SizedBox(width: 6),
          Text(label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? selectedColor : colors.textMuted,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
            )),
        ]),
      ),
    );
  }
}