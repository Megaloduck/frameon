import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_badge.dart';

// ── Clock config model ────────────────────────────────────────────────────

class ClockConfig {
  final bool is24h;
  final bool showDate;
  final bool showSeconds;
  final String timezone;
  final String ntpServer;
  final int brightness;

  const ClockConfig({
    this.is24h = true,
    this.showDate = true,
    this.showSeconds = false,
    this.timezone = 'UTC',
    this.ntpServer = 'pool.ntp.org',
    this.brightness = 128,
  });

  ClockConfig copyWith({
    bool? is24h,
    bool? showDate,
    bool? showSeconds,
    String? timezone,
    String? ntpServer,
    int? brightness,
  }) =>
      ClockConfig(
        is24h: is24h ?? this.is24h,
        showDate: showDate ?? this.showDate,
        showSeconds: showSeconds ?? this.showSeconds,
        timezone: timezone ?? this.timezone,
        ntpServer: ntpServer ?? this.ntpServer,
        brightness: brightness ?? this.brightness,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────

class ClockConfigNotifier extends Notifier<ClockConfig> {
  @override
  ClockConfig build() => const ClockConfig();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ClockConfig(
      is24h: prefs.getBool('clock_24h') ?? true,
      showDate: prefs.getBool('clock_date') ?? true,
      showSeconds: prefs.getBool('clock_seconds') ?? false,
      timezone: prefs.getString('clock_tz') ?? 'UTC',
      ntpServer: prefs.getString('clock_ntp') ?? 'pool.ntp.org',
      brightness: prefs.getInt('clock_brightness') ?? 128,
    );
  }

  Future<void> update(ClockConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('clock_24h', config.is24h);
    await prefs.setBool('clock_date', config.showDate);
    await prefs.setBool('clock_seconds', config.showSeconds);
    await prefs.setString('clock_tz', config.timezone);
    await prefs.setString('clock_ntp', config.ntpServer);
    await prefs.setInt('clock_brightness', config.brightness);
  }
}

final clockConfigProvider =
    NotifierProvider<ClockConfigNotifier, ClockConfig>(ClockConfigNotifier.new);

// ── Timezone data ─────────────────────────────────────────────────────────

class _TzOption {
  final String label;
  final String posix; // POSIX TZ string for ESP32 configTime()
  const _TzOption(this.label, this.posix);
}

const _timezones = [
  _TzOption('UTC', 'UTC0'),
  _TzOption('London (GMT/BST)', 'GMT0BST,M3.5.0/1,M10.5.0'),
  _TzOption('Paris / Berlin (CET)', 'CET-1CEST,M3.5.0,M10.5.0/3'),
  _TzOption('Helsinki (EET)', 'EET-2EEST,M3.5.0/3,M10.5.0/4'),
  _TzOption('Moscow (MSK)', 'MSK-3'),
  _TzOption('Dubai (GST)', 'GST-4'),
  _TzOption('Karachi (PKT)', 'PKT-5'),
  _TzOption('Dhaka (BST)', 'BST-6'),
  _TzOption('Bangkok (ICT)', 'ICT-7'),
  _TzOption('Singapore / KL (SGT)', 'SGT-8'),
  _TzOption('Manila (PHT)', 'PHT-8'),
  _TzOption('Tokyo (JST)', 'JST-9'),
  _TzOption('Sydney (AEST)', 'AEST-10AEDT,M10.1.0,M4.1.0/3'),
  _TzOption('Auckland (NZST)', 'NZST-12NZDT,M9.5.0,M4.1.0/3'),
  _TzOption('New York (EST)', 'EST5EDT,M3.2.0,M11.1.0'),
  _TzOption('Chicago (CST)', 'CST6CDT,M3.2.0,M11.1.0'),
  _TzOption('Denver (MST)', 'MST7MDT,M3.2.0,M11.1.0'),
  _TzOption('Los Angeles (PST)', 'PST8PDT,M3.2.0,M11.1.0'),
  _TzOption('São Paulo (BRT)', 'BRT3BRST,M10.3.0/0,M2.3.0/0'),
];

// ── Clock Screen ──────────────────────────────────────────────────────────

class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _isSending = false;
  String? _sendResult;
  final _ntpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(clockConfigProvider.notifier).load().then((_) {
      if (mounted) {
        _ntpController.text = ref.read(clockConfigProvider).ntpServer;
      }
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ntpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(clockConfigProvider);
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CLOCK'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: ConnectionBadge()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Live matrix preview ──────────────────────────────────
                _MatrixPreview(now: _now, config: config),
                const Gap(28),

                // ── Format ───────────────────────────────────────────────
                _SectionLabel('DISPLAY FORMAT'),
                const Gap(12),
                _SettingsCard(children: [
                  _ToggleRow(
                    icon: Icons.schedule_outlined,
                    label: '24-hour format',
                    value: config.is24h,
                    onChanged: (v) => _update(config.copyWith(is24h: v)),
                  ),
                  _Divider(),
                  _ToggleRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Show date',
                    value: config.showDate,
                    onChanged: (v) => _update(config.copyWith(showDate: v)),
                  ),
                  _Divider(),
                  _ToggleRow(
                    icon: Icons.timer_outlined,
                    label: 'Show seconds',
                    value: config.showSeconds,
                    onChanged: (v) => _update(config.copyWith(showSeconds: v)),
                  ),
                ]),
                const Gap(20),

                // ── Brightness ────────────────────────────────────────────
                _SectionLabel('BRIGHTNESS'),
                const Gap(12),
                _SettingsCard(children: [
                  _BrightnessRow(
                    value: config.brightness,
                    onChanged: (v) => _update(config.copyWith(brightness: v)),
                  ),
                ]),
                const Gap(20),

                // ── Timezone ──────────────────────────────────────────────
                _SectionLabel('TIMEZONE'),
                const Gap(12),
                _SettingsCard(children: [
                  _TimezoneRow(
                    value: config.timezone,
                    onChanged: (v) => _update(config.copyWith(timezone: v)),
                  ),
                ]),
                const Gap(20),

                // ── NTP ───────────────────────────────────────────────────
                _SectionLabel('NTP SERVER'),
                const Gap(12),
                _SettingsCard(children: [
                  _NtpRow(
                    controller: _ntpController,
                    onSubmit: (v) => _update(config.copyWith(ntpServer: v)),
                  ),
                ]),
                const Gap(32),

                // ── Send to device ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isSending
                        ? () => _sendToDevice(config)
                        : null,
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.bg),
                          )
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(_isSending ? 'Sending…' : 'Apply to matrix'),
                  ),
                ),
                if (!isConnected) ...[
                  const Gap(8),
                  const Text(
                    'Connect to your ESP32 in Setup to apply settings',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_sendResult != null) ...[
                  const Gap(10),
                  Text(
                    _sendResult!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _sendResult!.startsWith('✓')
                          ? AppColors.connected
                          : AppColors.disconnected,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Gap(24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _update(ClockConfig config) async {
    await ref.read(clockConfigProvider.notifier).update(config);
  }

  Future<void> _sendToDevice(ClockConfig config) async {
    setState(() {
      _isSending = true;
      _sendResult = null;
    });
    final api = ref.read(deviceApiServiceProvider);
    try {
      await api.setMode(const dynamic is dynamic ? null : null); // set clock mode
      await api.setClockFormat(config.is24h);
      await api.setClockTimezone(config.timezone);
      await api.setBrightness(config.brightness);
      // Send full clock config as single call
      await api.sendClockConfig(config);
      setState(() => _sendResult = '✓ Clock config applied');
    } catch (e) {
      setState(() => _sendResult = '✗ Failed: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }
}

// ── Matrix preview widget ─────────────────────────────────────────────────

class _MatrixPreview extends StatelessWidget {
  final DateTime now;
  final ClockConfig config;

  const _MatrixPreview({required this.now, required this.config});

  @override
  Widget build(BuildContext context) {
    final hour = config.is24h
        ? now.hour.toString().padLeft(2, '0')
        : (now.hour % 12 == 0 ? 12 : now.hour % 12)
            .toString()
            .padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    final amPm = now.hour < 12 ? 'AM' : 'PM';

    final months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC'
    ];
    final days = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    final dateStr =
        '${days[now.weekday - 1]} ${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Panel ratio label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'P4 32×64 MATRIX PREVIEW',
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 9,
                  color: AppColors.accent.withOpacity(0.4),
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Gap(16),

          // Simulated LED display
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AspectRatio(
              aspectRatio: 64 / 32,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF020408),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  children: [
                    // Dot grid overlay (simulates LED pixel grid)
                    CustomPaint(
                      painter: _DotGridPainter(),
                      size: Size.infinite,
                    ),
                    // Clock content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$hour:$minute',
                                style: TextStyle(
                                  fontFamily: 'SpaceMono',
                                  fontSize: config.showSeconds ? 22 : 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                  height: 1,
                                ),
                              ),
                              if (config.showSeconds) ...[
                                const SizedBox(width: 3),
                                Text(
                                  ':$second',
                                  style: TextStyle(
                                    fontFamily: 'SpaceMono',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.accent.withOpacity(0.6),
                                    height: 1,
                                  ),
                                ),
                              ],
                              if (!config.is24h) ...[
                                const SizedBox(width: 4),
                                Text(
                                  amPm,
                                  style: TextStyle(
                                    fontFamily: 'SpaceMono',
                                    fontSize: 10,
                                    color: AppColors.accent.withOpacity(0.5),
                                    height: 1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (config.showDate) ...[
                            const Gap(4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontFamily: 'SpaceMono',
                                fontSize: 9,
                                color: AppColors.clock.withOpacity(0.7),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(12),
          Text(
            'Live preview — updates every second',
            style: TextStyle(
              fontFamily: 'SpaceMono',
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0A1020)
      ..style = PaintingStyle.fill;
    const cols = 64;
    const rows = 32;
    final cw = size.width / cols;
    final rh = size.height / rows;
    final r = (cw * 0.28).clamp(0.5, 2.0);
    for (var c = 0; c < cols; c++) {
      for (var row = 0; row < rows; row++) {
        canvas.drawCircle(
          Offset(cw * c + cw / 2, rh * row + rh / 2),
          r,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.clock,
              letterSpacing: 1.2,
            ),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: AppColors.border,
      );
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.clock),
            const Gap(12),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
            const Spacer(),
            Switch(
              value: value,
              activeColor: AppColors.clock,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _BrightnessRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _BrightnessRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_medium_outlined,
                    size: 18, color: AppColors.clock),
                const Gap(12),
                const Text('Brightness',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textPrimary)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.clock.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${((value / 255) * 100).round()}%',
                    style: const TextStyle(
                        fontFamily: 'SpaceMono',
                        fontSize: 11,
                        color: AppColors.clock),
                  ),
                ),
              ],
            ),
            Slider(
              value: value.toDouble(),
              min: 10,
              max: 255,
              activeColor: AppColors.clock,
              inactiveColor: AppColors.border,
              onChanged: (v) => onChanged(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Low',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
                Text('Full',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      );
}

class _TimezoneRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TimezoneRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = _timezones.firstWhere(
      (t) => t.posix == value,
      orElse: () => _timezones.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.public_outlined, size: 18, color: AppColors.clock),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected.label,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textPrimary)),
                Text(
                  selected.posix,
                  style: const TextStyle(
                      fontFamily: 'SpaceMono',
                      fontSize: 10,
                      color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.expand_more,
                size: 20, color: AppColors.textSecondary),
            color: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.border),
            ),
            itemBuilder: (_) => _timezones
                .map((t) => PopupMenuItem(
                      value: t.posix,
                      child: Text(t.label,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary)),
                    ))
                .toList(),
            onSelected: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NtpRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  const _NtpRow({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_outlined,
                    size: 18, color: AppColors.clock),
                const Gap(12),
                const Text('NTP server',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),
            const Gap(10),
            TextField(
              controller: controller,
              style: const TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 13,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'pool.ntp.org',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check, size: 18, color: AppColors.clock),
                  onPressed: () => onSubmit(controller.text.trim()),
                  tooltip: 'Save',
                ),
              ),
              onSubmitted: onSubmit,
            ),
            const Gap(6),
            const Text(
              'Common: pool.ntp.org · time.google.com · time.cloudflare.com',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );
}
