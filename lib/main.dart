import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_theme.dart';
import 'core/theme_provider.dart';
import 'features/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read the persisted theme before the first frame so there is no
  // dark-mode flash when the user has saved light mode.
  final savedTheme = await ThemeNotifier.preload();

  runApp(
    ProviderScope(
      overrides: [
        // Seed the notifier with the already-loaded value. The notifier's
        // own build() will still call _load(), but state is already correct
        // so no rebuild will be triggered.
        themeProvider.overrideWith(() => _PreloadedThemeNotifier(savedTheme)),
      ],
      child: const FrameonApp(),
    ),
  );
}

/// A [ThemeNotifier] subclass that starts with a known [ThemeMode] rather
/// than always defaulting to dark before the async load resolves.
class _PreloadedThemeNotifier extends ThemeNotifier {
  final ThemeMode _initial;
  _PreloadedThemeNotifier(this._initial);

  @override
  ThemeMode build() {
    // Skip the async _load() flash — we already have the value.
    return _initial;
  }
}

class FrameonApp extends ConsumerWidget {
  const FrameonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp(
      title: 'Frameon',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}