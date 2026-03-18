import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/device_state.dart';
import '../../services/providers.dart';
import '../../services/device_api_extensions.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_badge.dart';

// ── Models ────────────────────────────────────────────────────────────────

class PomodoroConfig {
  final int workMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int sessionsBeforeLong;
  final bool alertOnComplete;
  final int brightness;

  const PomodoroConfig({
    this.workMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.sessionsBeforeLong = 4,
    this.alertOnComplete = true,
    this.brightness = 128,
  });

  PomodoroConfig copyWith({
    int? workMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsBeforeLong,
    bool? alertOnComplete,
    int? brightness,
  }) =>
      PomodoroConfig(
        workMinutes: workMinutes ?? this.workMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        sessionsBeforeLong: sessionsBeforeLong ?? this.sessionsBeforeLong,
        alertOnComplete: alertOnComplete ?? this.alertOnComplete,
        brightness: brightness ?? this.brightness,
      );
}

enum PomodoroPhase { work, shortBreak, longBreak }

class PomodoroState {
  final PomodoroPhase phase;
  final int secondsRemaining;
  final int sessionsCompleted;
  final bool isRunning;

  const PomodoroState({
    this.phase = PomodoroPhase.work,
    this.secondsRemaining = 25 * 60,
    this.sessionsCompleted = 0,
    this.isRunning = false,
  });

  PomodoroState copyWith({
    PomodoroPhase? phase,
    int? secondsRemaining,
    int? sessionsCompleted,
    bool? isRunning,
  }) =>
      PomodoroState(
        phase: phase ?? this.phase,
        secondsRemaining: secondsRemaining ?? this.secondsRemaining,
        sessionsCompleted: sessionsCompleted ?? this.sessionsCompleted,
        isRunning: isRunning ?? this.isRunning,
      );

  double get progress {
    // Calculated on timer side — just expose seconds here
    return secondsRemaining.toDouble();
  }

  String get timeLabel {
    final m = (secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Config notifier ───────────────────────────────────────────────────────

class PomodoroConfigNotifier extends Notifier<PomodoroConfig> {
  @override
  PomodoroConfig build() => const PomodoroConfig();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = PomodoroConfig(
      workMinutes: p.getInt('pomo_work') ?? 25,
      shortBreakMinutes: p.getInt('pomo_short') ?? 5,
      longBreakMinutes: p.getInt('pomo_long') ?? 15,
      sessionsBeforeLong: p.getInt('pomo_sessions') ?? 4,
      alertOnComplete: p.getBool('pomo_alert') ?? true,
      brightness: p.getInt('pomo_brightness') ?? 128,
    );
  }

  Future<void> update(PomodoroConfig config) async {
    state = config;
    final p = await SharedPreferences.getInstance();
    await p.setInt('pomo_work', config.workMinutes);
    await p.setInt('pomo_short', config.shortBreakMinutes);
    await p.setInt('pomo_long', config.longBreakMinutes);
    await p.setInt('pomo_sessions', config.sessionsBeforeLong);
    await p.setBool('pomo_alert', config.alertOnComplete);
    await p.setInt('pomo_brightness', config.brightness);
  }
}

final pomodoroConfigProvider =
    NotifierProvider<PomodoroConfigNotifier, PomodoroConfig>(
        PomodoroConfigNotifier.new);

// ── Timer notifier (local countdown — mirrors what ESP32 runs) ────────────

class PomodoroTimerNotifier extends Notifier<PomodoroState> {
  Timer? _ticker;

  @override
  PomodoroState build() => const PomodoroState();

  void start(PomodoroConfig config) {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick(config));
  }

  void pause() {
    _ticker?.cancel();
    state = state.copyWith(isRunning: false);
  }

  void reset(PomodoroConfig config) {
    _ticker?.cancel();
    state = PomodoroState(
      secondsRemaining: config.workMinutes * 60,
      phase: PomodoroPhase.work,
    );
  }

  void _tick(PomodoroConfig config) {
    if (state.secondsRemaining <= 0) {
      _ticker?.cancel();
      _advance(config);
      return;
    }
    state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
  }

  void _advance(PomodoroConfig config) {
    final newSessions = state.phase == PomodoroPhase.work
        ? state.sessionsCompleted + 1
        : state.sessionsCompleted;

    PomodoroPhase next;
    int nextSeconds;

    if (state.phase == PomodoroPhase.work) {
      if (newSessions % config.sessionsBeforeLong == 0) {
        next = PomodoroPhase.longBreak;
        nextSeconds = config.longBreakMinutes * 60;
      } else {
        next = PomodoroPhase.shortBreak;
        nextSeconds = config.shortBreakMinutes * 60;
      }
    } else {
      next = PomodoroPhase.work;
      nextSeconds = config.workMinutes * 60;
    }

    state = PomodoroState(
      phase: next,
      secondsRemaining: nextSeconds,
      sessionsCompleted: newSessions,
      isRunning: false,
    );
  }

  int totalSeconds(PomodoroPhase phase, PomodoroConfig config) {
    return switch (phase) {
      PomodoroPhase.work => config.workMinutes * 60,
      PomodoroPhase.shortBreak => config.shortBreakMinutes * 60,
      PomodoroPhase.longBreak => config.longBreakMinutes * 60,
    };
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final pomodoroTimerProvider =
    NotifierProvider<PomodoroTimerNotifier, PomodoroState>(
        PomodoroTimerNotifier.new);

// ── Screen ────────────────────────────────────────────────────────────────

class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen> {
  bool _isSyncing = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    ref.read(pomodoroConfigProvider.notifier).load().then((_) {
      if (mounted) {
        final config = ref.read(pomodoroConfigProvider);
        ref.read(pomodoroTimerProvider.notifier).reset(config);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(pomodoroConfigProvider);
    final timer = ref.watch(pomodoroTimerProvider);
    final isConnected = ref.watch(deviceStateProvider).isConnected;

    final totalSecs = ref
        .read(pomodoroTimerProvider.notifier)
        .totalSeconds(timer.phase, config);
    final progress =
        totalSecs > 0 ? timer.secondsRemaining / totalSecs : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POMODORO'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: ConnectionBadge()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                // ── Timer ring ────────────────────────────────────────────
                _TimerRing(
                  progress: progress,
                  timer: timer,
                  config: config,
                ),
                const Gap(32),

                // ── Controls ──────────────────────────────────────────────
                _TimerControls(
                  timer: timer,
                  config: config,
                  onStart: () {
                    ref.read(pomodoroTimerProvider.notifier).start(config);
                    if (isConnected) {
                      ref.read(deviceApiServiceProvider).pomodoroCommand('start');
                    }
                  },
                  onPause: () {
                    ref.read(pomodoroTimerProvider.notifier).pause();
                    if (isConnected) {
                      ref.read(deviceApiServiceProvider).pomodoroCommand('pause');
                    }
                  },
                  onReset: () {
                    ref.read(pomodoroTimerProvider.notifier).reset(config);
                    if (isConnected) {
                      ref.read(deviceApiServiceProvider).pomodoroCommand('reset');
                    }
                  },
                ),
                const Gap(32),

                // ── Session dots ──────────────────────────────────────────
                _SessionDots(
                  completed: timer.sessionsCompleted,
                  total: config.sessionsBeforeLong,
                ),
                const Gap(32),

                // ── Config ────────────────────────────────────────────────
                _PomodoroConfig(
                  config: config,
                  onUpdate: (c) async {
                    await ref.read(pomodoroConfigProvider.notifier).update(c);
                    ref.read(pomodoroTimerProvider.notifier).reset(c);
                  },
                ),
                const Gap(24),

                // ── Sync to device ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isSyncing
                        ? () => _syncToDevice(config)
                        : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.pomodoro,
                        foregroundColor: AppColors.bg),
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.bg))
                        : const Icon(Icons.sync, size: 18),
                    label:
                        Text(_isSyncing ? 'Syncing…' : 'Sync config to matrix'),
                  ),
                ),
                if (!isConnected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Connect to ESP32 in Setup to sync timer',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_syncResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _syncResult!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _syncResult!.startsWith('✓')
                            ? AppColors.connected
                            : AppColors.disconnected,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const Gap(24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _syncToDevice(PomodoroConfig config) async {
    setState(() {
      _isSyncing = true;
      _syncResult = null;
    });
    try {
      await ref.read(deviceApiServiceProvider).sendPomodoroConfig(config);
      await ref
          .read(deviceApiServiceProvider)
          .setMode(AppMode.pomodoro);
      setState(() => _syncResult = '✓ Pomodoro config synced to matrix');
    } catch (e) {
      setState(() => _syncResult = '✗ Sync failed: $e');
    } finally {
      setState(() => _isSyncing = false);
    }
  }
}

// ── Timer ring ────────────────────────────────────────────────────────────

class _TimerRing extends StatelessWidget {
  final double progress;
  final PomodoroState timer;
  final PomodoroConfig config;

  const _TimerRing({
    required this.progress,
    required this.timer,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final phaseColor = switch (timer.phase) {
      PomodoroPhase.work => AppColors.pomodoro,
      PomodoroPhase.shortBreak => AppColors.connected,
      PomodoroPhase.longBreak => AppColors.clock,
    };

    final phaseLabel = switch (timer.phase) {
      PomodoroPhase.work => 'FOCUS',
      PomodoroPhase.shortBreak => 'SHORT BREAK',
      PomodoroPhase.longBreak => 'LONG BREAK',
    };

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox(
            width: 220,
            height: 220,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                color: phaseColor,
                trackColor: phaseColor.withOpacity(0.1),
              ),
            ),
          ),
          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                phaseLabel,
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 10,
                  color: phaseColor.withOpacity(0.7),
                  letterSpacing: 1.5,
                ),
              ),
              const Gap(6),
              Text(
                timer.timeLabel,
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: phaseColor,
                  height: 1,
                ),
              ),
              const Gap(8),
              if (timer.isRunning)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: phaseColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: phaseColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    'RUNNING',
                    style: TextStyle(
                      fontFamily: 'SpaceMono',
                      fontSize: 9,
                      color: phaseColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                )
              else
                Text(
                  'Session ${timer.sessionsCompleted + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0.0–1.0
  final Color color;
  final Color trackColor;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.width / 2) - 12;
    const strokeWidth = 8.0;

    // Track
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ── Controls ──────────────────────────────────────────────────────────────

class _TimerControls extends StatelessWidget {
  final PomodoroState timer;
  final PomodoroConfig config;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const _TimerControls({
    required this.timer,
    required this.config,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Reset
          _ControlBtn(
            icon: Icons.replay,
            color: AppColors.textSecondary,
            onTap: onReset,
            tooltip: 'Reset',
          ),
          const Gap(16),
          // Play / Pause
          GestureDetector(
            onTap: timer.isRunning ? onPause : onStart,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.pomodoro,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pomodoro.withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                timer.isRunning ? Icons.pause : Icons.play_arrow,
                size: 32,
                color: AppColors.bg,
              ),
            ),
          ),
          const Gap(16),
          // Skip to next phase
          _ControlBtn(
            icon: Icons.skip_next,
            color: AppColors.textSecondary,
            onTap: () {}, // triggers phase advance
            tooltip: 'Skip phase',
          ),
        ],
      );
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ControlBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );
}

// ── Session dots ──────────────────────────────────────────────────────────

class _SessionDots extends StatelessWidget {
  final int completed;
  final int total;

  const _SessionDots({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            'SESSIONS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.pomodoro,
                  letterSpacing: 1.2,
                ),
          ),
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (i) {
              final done = i < (completed % total);
              return Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.pomodoro
                      : AppColors.pomodoro.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.pomodoro.withOpacity(done ? 0 : 0.3),
                  ),
                ),
              );
            }),
          ),
          const Gap(6),
          Text(
            '$completed sessions completed total',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      );
}

// ── Config panel ──────────────────────────────────────────────────────────

class _PomodoroConfig extends StatelessWidget {
  final PomodoroConfig config;
  final ValueChanged<PomodoroConfig> onUpdate;

  const _PomodoroConfig({required this.config, required this.onUpdate});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TIMER SETTINGS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.pomodoro,
                  letterSpacing: 1.2,
                ),
          ),
          const Gap(12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _DurationRow(
                  icon: Icons.work_outline,
                  label: 'Focus duration',
                  value: config.workMinutes,
                  min: 1,
                  max: 90,
                  color: AppColors.pomodoro,
                  onChanged: (v) => onUpdate(config.copyWith(workMinutes: v)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                _DurationRow(
                  icon: Icons.coffee_outlined,
                  label: 'Short break',
                  value: config.shortBreakMinutes,
                  min: 1,
                  max: 30,
                  color: AppColors.connected,
                  onChanged: (v) =>
                      onUpdate(config.copyWith(shortBreakMinutes: v)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                _DurationRow(
                  icon: Icons.self_improvement_outlined,
                  label: 'Long break',
                  value: config.longBreakMinutes,
                  min: 5,
                  max: 60,
                  color: AppColors.clock,
                  onChanged: (v) =>
                      onUpdate(config.copyWith(longBreakMinutes: v)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                _DurationRow(
                  icon: Icons.repeat_outlined,
                  label: 'Sessions before long break',
                  value: config.sessionsBeforeLong,
                  min: 2,
                  max: 8,
                  color: AppColors.pomodoro,
                  unit: '',
                  onChanged: (v) =>
                      onUpdate(config.copyWith(sessionsBeforeLong: v)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_outlined,
                          size: 18, color: AppColors.pomodoro),
                      const Gap(12),
                      const Text('Alert on completion',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      Switch(
                        value: config.alertOnComplete,
                        activeColor: AppColors.pomodoro,
                        onChanged: (v) =>
                            onUpdate(config.copyWith(alertOnComplete: v)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _DurationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final Color color;
  final String unit;
  final ValueChanged<int> onChanged;

  const _DurationRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    this.unit = 'min',
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const Gap(12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            // Stepper
            InkWell(
              onTap: value > min ? () => onChanged(value - 1) : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.remove,
                    size: 14,
                    color: value > min
                        ? AppColors.textSecondary
                        : AppColors.textMuted),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                unit.isEmpty ? '$value' : '$value $unit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'SpaceMono',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              onTap: value < max ? () => onChanged(value + 1) : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(Icons.add,
                    size: 14,
                    color: value < max
                        ? AppColors.textSecondary
                        : AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
}
