import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frameon/core/ble/ble_uuids.dart';
import '../../core/app_theme.dart';
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_manager.dart';
import '../ui/connection_status.dart';
import '../ui/theme_switcher.dart';
import '../ui/led_matrix_preview.dart';

enum ClockFormat { h24, h12 }
enum ClockStyle { digital, minimal, blocky }
enum ClockColor { green, white, amber, cyan, red }

const Map<ClockColor, Color> kClockColors = {
  ClockColor.green:  Color(0xFF00FF41),
  ClockColor.white:  Color(0xFFFFFFFF),
  ClockColor.amber:  Color(0xFFFFB300),
  ClockColor.cyan:   Color(0xFF00B4FF),
  ClockColor.red:    Color(0xFFFF2D2D),
};

class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  ClockFormat _format = ClockFormat.h24;
  ClockStyle  _style  = ClockStyle.digital;
  ClockColor  _color  = ClockColor.green;
  bool _showSeconds = false;
  bool _showDate    = false;
  bool _blinkColon  = true;
  bool _isLive      = false;

  late Timer _ticker;
  DateTime _now = DateTime.now();
  bool _colonVisible = true;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        _now = DateTime.now();
        _colonVisible = !_colonVisible;
      });
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  // ── Time formatting ───────────────────────────────────────────

  String get _timeString {
    final h = _format == ClockFormat.h24
        ? _now.hour.toString().padLeft(2, '0')
        : (_now.hour % 12 == 0 ? 12 : _now.hour % 12)
            .toString()
            .padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    final colon = _blinkColon && _colonVisible ? ':' : ' ';
    return _showSeconds ? '$h$colon$m$colon$s' : '$h$colon$m';
  }

  String get _dateString {
    const months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC',
    ];
    return '${_now.day.toString().padLeft(2,'0')} '
        '${months[_now.month-1]} ${_now.year}';
  }

  String get _amPm => _now.hour < 12 ? 'AM' : 'PM';

  // ── Device commands ───────────────────────────────────────────

  Future<void> _toggleClockMode() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (!_isLive) {
      if (bleManager.state != FrameonConnectionState.connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No device connected.',
              style: TextStyle(fontFamily: 'monospace')),
        ));
        return;
      }
      try {
        await bleService.setMode(kModeClock);
        await bleService.syncClock(
          is24h: _format == ClockFormat.h24,
          showSeconds: _showSeconds,
          showDate: _showDate,
        );
        setState(() => _isLive = true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'monospace')),
        ));
      }
    } else {
      setState(() => _isLive = false);
    }
  }

  Future<void> _syncTime() async {
    final bleManager = ref.read(bleManagerProvider);
    final bleService = ref.read(bleServiceProvider);

    if (bleManager.state != FrameonConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No device connected.',
            style: TextStyle(fontFamily: 'monospace')),
      ));
      return;
    }
    try {
      await bleService.syncClock(
        is24h: _format == ClockFormat.h24,
        showSeconds: _showSeconds,
        showDate: _showDate,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ Time synced: ${_now.toIso8601String()}',
            style: const TextStyle(fontFamily: 'monospace')),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync error: $e',
            style: const TextStyle(fontFamily: 'monospace')),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = kClockColors[_color]!;
    final bleManager = ref.watch(bleManagerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(children: [
        _buildHeader(colors, accent),
        ConnectionStatusBar(
          manager: bleManager,
          onTap: () => DeviceScannerSheet.show(context, bleManager),
        ),
        Expanded(
          child: Row(children: [
            Expanded(child: _buildPreviewPanel(colors, accent)),
            _buildRightPanel(colors, accent),
          ]),
        ),
        _buildStatusBar(colors, accent),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader(AppColors colors, Color accent) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.arrow_back_ios, color: colors.textMuted, size: 16),
        ),
        const SizedBox(width: 16),
        Text('CLOCK', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: colors.textPrimary, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        Text('LED MATRIX DISPLAY', style: TextStyle(
          fontSize: 11, color: colors.textMuted,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        if (_isLive) _LiveBadge(color: accent),
        const SizedBox(width: 8),
        const ThemeToggleButton(),
      ]),
    );
  }

  // ── Preview panel ─────────────────────────────────────────────

  Widget _buildPreviewPanel(AppColors colors, Color accent) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              // The clock face simulates the LED panel — always black
              color: Colors.black,
              border: Border.all(color: accent.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(
                color: accent.withValues(alpha: 0.05),
                blurRadius: 40, spreadRadius: 4,
              )],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeString,
                    style: TextStyle(
                      fontSize: _style == ClockStyle.blocky ? 72 : 64,
                      fontWeight: FontWeight.bold,
                      color: accent,
                      fontFamily: 'monospace',
                      letterSpacing: _style == ClockStyle.minimal ? 8 : 4,
                      shadows: [Shadow(
                          color: accent.withValues(alpha: 0.5), blurRadius: 20)],
                    ),
                  ),
                  if (_format == ClockFormat.h12) ...[
                    const SizedBox(height: 4),
                    Text(_amPm, style: TextStyle(
                      fontSize: 18,
                      color: accent.withValues(alpha: 0.6),
                      fontFamily: 'monospace', letterSpacing: 4,
                    )),
                  ],
                  if (_showDate) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: 200, height: 1,
                      color: accent.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 12),
                    Text(_dateString, style: TextStyle(
                      fontSize: 16,
                      color: accent.withValues(alpha: 0.5),
                      fontFamily: 'monospace', letterSpacing: 3,
                    )),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildMatrixSimulation(colors, accent),
      ]),
    );
  }

  Widget _buildMatrixSimulation(AppColors colors, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _SectionLabel('MATRIX PREVIEW', colors),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                _color.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 8, color: accent,
                  fontFamily: 'monospace', letterSpacing: 0.8,
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        // height: 140 → width = 280 (2:1 guaranteed)
        LedMatrixPreview(
          height: 140,
          label: '64 × 32  ·  '
              '${_format == ClockFormat.h24 ? "24H" : "12H"}'
              '${_showDate ? "  ·  DATE" : ""}',
          content: ClockLedContent(
            timeString: _timeString,
            dateString: _showDate ? _dateString : null,
            amPm: _format == ClockFormat.h12 ? _amPm : null,
            color: accent,
          ),
        ),
      ],
    );
  }
  
  // ── Right panel ───────────────────────────────────────────────

  Widget _buildRightPanel(AppColors colors, Color accent) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('COLOR', colors),
            const SizedBox(height: 10),
            _buildColorRow(colors),
            const SizedBox(height: 20),
            _SectionLabel('FORMAT', colors),
            const SizedBox(height: 10),
            _buildFormatToggle(colors, accent),
            const SizedBox(height: 20),
            _SectionLabel('STYLE', colors),
            const SizedBox(height: 10),
            _buildStyleSelector(colors, accent),
            const SizedBox(height: 20),
            _SectionLabel('OPTIONS', colors),
            const SizedBox(height: 10),
            _buildToggle('SHOW SECONDS', _showSeconds, accent, colors,
                (v) => setState(() => _showSeconds = v)),
            const SizedBox(height: 8),
            _buildToggle('SHOW DATE', _showDate, accent, colors,
                (v) => setState(() => _showDate = v)),
            const SizedBox(height: 8),
            _buildToggle('BLINK COLON', _blinkColon, accent, colors,
                (v) => setState(() => _blinkColon = v)),
            const SizedBox(height: 24),
            _ActionButton(
              label: _isLive ? 'STOP CLOCK' : 'SEND TO DEVICE',
              color: _isLive ? colors.accentRed : colors.accentBlue,
              onTap: _toggleClockMode,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'SYNC TIME',
              color: accent,
              onTap: _syncTime,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorRow(AppColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: ClockColor.values.map((c) {
        final color = kClockColors[c]!;
        final selected = _color == c;
        return GestureDetector(
          onTap: () => setState(() => _color = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border.all(
                color: selected ? color : colors.border,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: selected
                  ? [BoxShadow(
                      color: color.withValues(alpha: 0.4), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFormatToggle(AppColors colors, Color accent) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: [
        _FormatTab('24H', _format == ClockFormat.h24, accent, colors,
            () => setState(() => _format = ClockFormat.h24)),
        _FormatTab('12H', _format == ClockFormat.h12, accent, colors,
            () => setState(() => _format = ClockFormat.h12)),
      ]),
    );
  }

  Widget _buildStyleSelector(AppColors colors, Color accent) {
    const styles = [
      (ClockStyle.digital, 'DIGITAL', 'Standard LED font'),
      (ClockStyle.minimal, 'MINIMAL', 'Wide spaced, clean'),
      (ClockStyle.blocky,  'BLOCKY',  'Large bold digits'),
    ];
    return Column(
      children: styles.map((s) {
        final active = _style == s.$1;
        return GestureDetector(
          onTap: () => setState(() => _style = s.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
              border: Border.all(
                color: active ? accent : colors.border,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? accent : colors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$2, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: active ? accent : colors.textSecondary,
                  letterSpacing: 1, fontFamily: 'monospace',
                )),
                Text(s.$3, style: TextStyle(
                  fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
                )),
              ]),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggle(
    String label,
    bool value,
    Color accent,
    AppColors colors,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32, height: 18,
          decoration: BoxDecoration(
            color: value
                ? colors.toggleActive.withValues(alpha: 0.15)
                : colors.toggleInactive,
            border: Border.all(
              color: value ? colors.toggleActive : colors.border,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment:
                value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: value ? colors.toggleActive : colors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
          fontSize: 10, color: colors.textSecondary,
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ]),
    );
  }

  // ── Status bar ────────────────────────────────────────────────

  Widget _buildStatusBar(AppColors colors, Color accent) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('FORMAT',
            _format == ClockFormat.h24 ? '24H' : '12H', accent, colors),
        const SizedBox(width: 24),
        _StatusItem('COLOR', _color.name.toUpperCase(), accent, colors),
        const SizedBox(width: 24),
        _StatusItem('STYLE', _style.name.toUpperCase(),
            colors.textSecondary, colors),
        const Spacer(),
        Text(
          _now.toLocal().toString().substring(0, 19),
          style: TextStyle(
            fontSize: 9, color: colors.textMuted, fontFamily: 'monospace'),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  final Color color;
  const _LiveBadge({required this.color});
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color
            .withValues(alpha: 0.05 + _ctrl.value * 0.1),
        border: Border.all(
          color: widget.color
              .withValues(alpha: 0.4 + _ctrl.value * 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
              color: widget.color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('LIVE', style: TextStyle(
          fontSize: 9, color: widget.color,
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
      ]),
    ),
  );
}

class _FormatTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final AppColors colors;
  final VoidCallback onTap;
  const _FormatTab(this.label, this.active, this.accent, this.colors, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold,
          color: active ? accent : colors.textMuted,
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppColors colors;
  const _SectionLabel(this.text, this.colors);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(
    fontSize: 9, letterSpacing: 2, color: colors.textMuted,
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, textAlign: TextAlign.center, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold, color: color,
        letterSpacing: 1.5, fontFamily: 'monospace',
      )),
    ),
  );
}

class _StatusItem extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  final AppColors colors;
  const _StatusItem(this.label, this.value, this.valueColor, this.colors);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: TextStyle(
      fontSize: 10, color: colors.textMuted, fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor, fontFamily: 'monospace',
    )),
  ]);
}