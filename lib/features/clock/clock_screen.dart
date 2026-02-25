import 'dart:async';
import 'package:flutter/material.dart';

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

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  ClockFormat _format = ClockFormat.h24;
  ClockStyle _style = ClockStyle.digital;
  ClockColor _color = ClockColor.green;
  bool _showSeconds = false;
  bool _showDate = false;
  bool _blinkColon = true;
  bool _isLive = false;

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

  String get _timeString {
    final h = _format == ClockFormat.h24
        ? _now.hour.toString().padLeft(2, '0')
        : (_now.hour % 12 == 0 ? 12 : _now.hour % 12).toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    final colon = _blinkColon && _colonVisible ? ':' : ' ';
    return _showSeconds ? '$h$colon$m$colon$s' : '$h$colon$m';
  }

  String get _dateString {
    final months = ['JAN','FEB','MAR','APR','MAY','JUN',
                    'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${_now.day.toString().padLeft(2,'0')} ${months[_now.month-1]} ${_now.year}';
  }

  String get _amPm => _now.hour < 12 ? 'AM' : 'PM';

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = kClockColors[_color]!;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Column(children: [
        _buildHeader(accent),
        Expanded(
          child: Row(children: [
            Expanded(child: _buildPreviewPanel(accent)),
            _buildRightPanel(accent),
          ]),
        ),
        _buildStatusBar(accent),
      ]),
    );
  }

  Widget _buildHeader(Color accent) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios, color: Color(0xFF444444), size: 16),
        ),
        const SizedBox(width: 16),
        const Text('CLOCK', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: Colors.white, fontFamily: 'monospace',
        )),
        const SizedBox(width: 10),
        const Text('LED MATRIX DISPLAY', style: TextStyle(
          fontSize: 11, color: Color(0xFF444444),
          letterSpacing: 1.5, fontFamily: 'monospace',
        )),
        const Spacer(),
        if (_isLive)
          _LiveBadge(color: accent),
      ]),
    );
  }

  Widget _buildPreviewPanel(Color accent) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        // Large clock display
        Expanded(
          child: Container(
            decoration: BoxDecoration(
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
                  // Clock time
                  Text(
                    _timeString,
                    style: TextStyle(
                      fontSize: _style == ClockStyle.blocky ? 72 : 64,
                      fontWeight: FontWeight.bold,
                      color: accent,
                      fontFamily: 'monospace',
                      letterSpacing: _style == ClockStyle.minimal ? 8 : 4,
                      shadows: [Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 20)],
                    ),
                  ),
                  if (_format == ClockFormat.h12) ...[
                    const SizedBox(height: 4),
                    Text(_amPm, style: TextStyle(
                      fontSize: 18, color: accent.withValues(alpha: 0.6),
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
                      fontSize: 16, color: accent.withValues(alpha: 0.5),
                      fontFamily: 'monospace', letterSpacing: 3,
                    )),
                  ],
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Matrix simulation strip (64×32 ratio)
        _buildMatrixSimulation(accent),
      ]),
    );
  }

  Widget _buildMatrixSimulation(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const _SectionLabel('MATRIX PREVIEW'),
          const Spacer(),
          Text('64 × 32 LED', style: TextStyle(
            fontSize: 9, color: accent.withValues(alpha: 0.3), fontFamily: 'monospace',
          )),
        ]),
        const SizedBox(height: 8),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: accent.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timeString.replaceAll(' ', ':'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: accent,
                    fontFamily: 'monospace',
                    shadows: [Shadow(color: accent.withValues(alpha: 0.6), blurRadius: 8)],
                  ),
                ),
                if (_showDate)
                  Text(_dateString, style: TextStyle(
                    fontSize: 7, color: accent.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                  )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightPanel(Color accent) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(left: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('COLOR'),
            const SizedBox(height: 10),
            _buildColorRow(),
            const SizedBox(height: 20),
            const _SectionLabel('FORMAT'),
            const SizedBox(height: 10),
            _buildFormatToggle(accent),
            const SizedBox(height: 20),
            const _SectionLabel('STYLE'),
            const SizedBox(height: 10),
            _buildStyleSelector(accent),
            const SizedBox(height: 20),
            const _SectionLabel('OPTIONS'),
            const SizedBox(height: 10),
            _buildToggle('SHOW SECONDS', _showSeconds, accent,
                (v) => setState(() => _showSeconds = v)),
            const SizedBox(height: 8),
            _buildToggle('SHOW DATE', _showDate, accent,
                (v) => setState(() => _showDate = v)),
            const SizedBox(height: 8),
            _buildToggle('BLINK COLON', _blinkColon, accent,
                (v) => setState(() => _blinkColon = v)),
            const SizedBox(height: 24),
            _ActionButton(
              label: _isLive ? 'STOP CLOCK' : 'SEND TO DEVICE',
              color: _isLive ? const Color(0xFFFF2D2D) : const Color(0xFF00B4FF),
              onTap: () {
                setState(() => _isLive = !_isLive);
                // TODO: send clock config to BLE manager
              },
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'SYNC TIME',
              color: accent,
              onTap: () {
                // TODO: send current epoch to ESP32
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Syncing ${_now.toIso8601String()}',
                    style: const TextStyle(fontFamily: 'monospace')),
                  backgroundColor: const Color(0xFF0D0D1A),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorRow() {
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
                color: selected ? color : const Color(0xFF222222),
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8)] : null,
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

  Widget _buildFormatToggle(Color accent) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF222222)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: [
        _FormatTab('24H', _format == ClockFormat.h24, accent,
            () => setState(() => _format = ClockFormat.h24)),
        _FormatTab('12H', _format == ClockFormat.h12, accent,
            () => setState(() => _format = ClockFormat.h12)),
      ]),
    );
  }

  Widget _buildStyleSelector(Color accent) {
    const styles = [
      (ClockStyle.digital, 'DIGITAL',  'Standard LED font'),
      (ClockStyle.minimal, 'MINIMAL',  'Wide spaced, clean'),
      (ClockStyle.blocky,  'BLOCKY',   'Large bold digits'),
    ];
    return Column(
      children: styles.map((s) {
        final active = _style == s.$1;
        return GestureDetector(
          onTap: () => setState(() => _style = s.$1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
              border: Border.all(
                color: active ? accent : const Color(0xFF222222),
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? accent : const Color(0xFF333333),
                ),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$2, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: active ? accent : const Color(0xFF555555),
                  letterSpacing: 1, fontFamily: 'monospace',
                )),
                Text(s.$3, style: const TextStyle(
                  fontSize: 9, color: Color(0xFF333333), fontFamily: 'monospace',
                )),
              ]),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggle(String label, bool value, Color accent, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(children: [
        Container(
          width: 32, height: 18,
          decoration: BoxDecoration(
            color: value ? accent.withValues(alpha: 0.15) : const Color(0xFF1A1A2E),
            border: Border.all(color: value ? accent : const Color(0xFF333333)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: value ? accent : const Color(0xFF333333),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(
          fontSize: 10, color: Color(0xFF555555),
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ]),
    );
  }

  Widget _buildStatusBar(Color accent) {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatusItem('FORMAT', _format == ClockFormat.h24 ? '24H' : '12H', accent),
        const SizedBox(width: 24),
        _StatusItem('COLOR', _color.name.toUpperCase(), accent),
        const SizedBox(width: 24),
        _StatusItem('STYLE', _style.name.toUpperCase(), const Color(0xFF666666)),
        const Spacer(),
        Text(_now.toLocal().toString().substring(0, 19),
          style: const TextStyle(fontSize: 9, color: Color(0xFF333333),
            fontFamily: 'monospace')),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
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
        color: widget.color.withValues(alpha: 0.05 + _ctrl.value * 0.1),
        border: Border.all(color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Container(width: 5, height: 5,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
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
  final VoidCallback onTap;
  const _FormatTab(this.label, this.active, this.accent, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold,
          color: active ? accent : const Color(0xFF444444),
          letterSpacing: 1, fontFamily: 'monospace',
        )),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    fontSize: 9, letterSpacing: 2, color: Color(0xFF333333),
    fontWeight: FontWeight.bold, fontFamily: 'monospace',
  ));
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.color, required this.onTap});
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
  const _StatusItem(this.label, this.value, this.valueColor);
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$label: ', style: const TextStyle(
      fontSize: 10, color: Color(0xFF333333), fontFamily: 'monospace',
    )),
    Text(value, style: TextStyle(
      fontSize: 10, color: valueColor, fontFamily: 'monospace',
    )),
  ]);
}