import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frameon/screens/shell_screen.dart';
import 'package:frameon/theme/app_theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FrameonApp()));
}

class FrameonApp extends ConsumerWidget {
  const FrameonApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Frameon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ShellScreen(),
    );
  }
}