import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/ui/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: FrameonApp()));
}

class FrameonApp extends StatelessWidget {
  const FrameonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frameon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF41),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        fontFamily: 'monospace',
      ),
      home: const HomeScreen(),
    );
  }
}