import 'package:flutter/material.dart';
import '../pixel_editor/pixel_canvas_editor.dart';
import '../spotify/spotify_screen.dart';
import '../media/media_upload_screen.dart';
import '../clock/clock_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00FF41), Color(0xFF00B4FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('F', style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black,
                )),
              ),
            ),
            const SizedBox(height: 24),
            const Text('FRAMEON', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold,
              letterSpacing: 6, color: Colors.white, fontFamily: 'monospace',
            )),
            const SizedBox(height: 8),
            const Text('32 × 64 LED MATRIX CONTROLLER', style: TextStyle(
              fontSize: 11, color: Color(0xFF444444),
              letterSpacing: 2, fontFamily: 'monospace',
            )),
            const SizedBox(height: 48),
            _MenuButton(
              label: 'PIXEL EDITOR',
              subtitle: 'Draw and upload pixel art',
              color: const Color(0xFF00FF41),
              onTap: () => _push(context, const PixelCanvasEditor()),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              label: 'MEDIA UPLOAD',
              subtitle: 'Send images and GIFs',
              color: const Color(0xFFFFE600),
              onTap: () => _push(context, const MediaUploadScreen()),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              label: 'CLOCK',
              subtitle: 'Configure clock display',
              color: const Color(0xFF00B4FF),
              onTap: () => _push(context, const ClockScreen()),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              label: 'SPOTIFY',
              subtitle: 'Now playing & controls',
              color: const Color(0xFF1DB954),
              onTap: () => _push(context, const SpotifyScreen()),
            ),
            const SizedBox(height: 12),
            _MenuButton(
              label: 'DEVICE SETTINGS',
              subtitle: 'Brightness, WiFi, firmware',
              color: const Color(0xFF888888),
              onTap: () {}, // TODO: SettingsScreen
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

class _MenuButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          border: Border.all(color: color.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Container(
            width: 4, height: 36,
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: color,
              letterSpacing: 1.5, fontFamily: 'monospace',
            )),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(
              fontSize: 10, color: Color(0xFF555555), fontFamily: 'monospace',
            )),
          ]),
          const Spacer(),
          Text('›', style: TextStyle(fontSize: 20, color: color.withOpacity(0.4))),
        ]),
      ),
    );
  }
}