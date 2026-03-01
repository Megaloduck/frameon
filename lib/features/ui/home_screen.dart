import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pixel_editor/pixel_canvas_editor.dart';
import '../spotify/spotify_screen.dart';
import '../media/media_upload_screen.dart';
import '../clock/clock_screen.dart';
import '../font_text/font_text_screen.dart';   // ← new
import '../../core/ble/ble_providers.dart';
import '../../core/app_theme.dart';
import 'connection_status.dart';
import 'theme_switcher.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleManager = ref.watch(bleManagerProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: colors.headerBg,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FF41), Color(0xFF00B4FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text('F', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold,
                      color: Colors.black,
                    )),
                  ),
                ),
                const SizedBox(width: 10),
                Text('FRAMEON', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold,
                  letterSpacing: 2, color: colors.textPrimary,
                  fontFamily: 'monospace',
                )),
                const Spacer(),
                const ThemeToggleButton(),
              ]),
            ),
          ),

          // ── Main content ─────────────────────────────────────────
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00FF41), Color(0xFF00B4FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FF41).withValues(alpha: 0.25),
                            blurRadius: 24, offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('F', style: TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold,
                          color: Colors.black,
                        )),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('FRAMEON', style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold,
                      letterSpacing: 6, color: colors.textPrimary,
                      fontFamily: 'monospace',
                    )),
                    const SizedBox(height: 6),
                    Text('32 × 64 LED MATRIX CONTROLLER', style: TextStyle(
                      fontSize: 10, color: colors.textMuted,
                      letterSpacing: 2, fontFamily: 'monospace',
                    )),

                    const SizedBox(height: 28),
                    const ThemeSwitcherPill(),

                    const SizedBox(height: 36),
                    _MenuButton(
                      label: 'PIXEL EDITOR',
                      subtitle: 'Draw and upload pixel art',
                      color: colors.accent,
                      colors: colors,
                      onTap: () => _push(context, const PixelCanvasEditor()),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      label: 'MEDIA UPLOAD',
                      subtitle: 'Send images and GIFs',
                      color: colors.accentYellow,
                      colors: colors,
                      onTap: () => _push(context, const MediaUploadScreen()),
                    ),
                    const SizedBox(height: 10),
                    // ── NEW ─────────────────────────────────────────
                    _MenuButton(
                      label: 'FONT TEXT',
                      subtitle: 'Render custom .ttf / .otf to matrix',
                      color: colors.accentBlue,
                      colors: colors,
                      onTap: () => _push(context, const FontTextScreen()),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      label: 'CLOCK',
                      subtitle: 'Configure clock display',
                      color: colors.accentBlue,
                      colors: colors,
                      onTap: () => _push(context, const ClockScreen()),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      label: 'SPOTIFY',
                      subtitle: 'Now playing & controls',
                      color: colors.accentSpotify,
                      colors: colors,
                      onTap: () => _push(context, const SpotifyScreen()),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      label: 'DEVICE SETTINGS',
                      subtitle: 'Brightness, WiFi, firmware',
                      color: colors.textSecondary,
                      colors: colors,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── BLE status ───────────────────────────────────────────
          ConnectionStatusBar(
            manager: bleManager,
            onTap: () => DeviceScannerSheet.show(context, bleManager),
          ),
        ],
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
  final AppColors colors;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.colors,
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
          color: colors.surface,
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: colors.isDark ? 0.04 : 0.06),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
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
              fontSize: 12, fontWeight: FontWeight.bold, color: color,
              letterSpacing: 1.5, fontFamily: 'monospace',
            )),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(
              fontSize: 10, color: colors.textSecondary,
              fontFamily: 'monospace',
            )),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, color: color.withValues(alpha: 0.4), size: 18),
        ]),
      ),
    );
  }
}