import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/ble/ble_manager.dart';

/// Compact BLE connection status bar shown at the top of feature screens.
/// Pass [manager] and it self-updates via stream subscription.
class ConnectionStatusBar extends StatefulWidget {
  final BleManager manager;
  final VoidCallback? onTap;

  const ConnectionStatusBar({
    super.key,
    required this.manager,
    this.onTap,
  });

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar> {
  late FrameonConnectionState _state;
  StreamSubscription<FrameonConnectionState>? _sub;

  @override
  void initState() {
    super.initState();
    _state = widget.manager.state;
    _sub = widget.manager.connectionStateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void didUpdateWidget(ConnectionStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      _sub?.cancel();
      _state = widget.manager.state;
      _sub = widget.manager.connectionStateStream.listen((s) {
        if (mounted) setState(() => _state = s);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _stateInfo(_state);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: 0.2)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _StateDot(
            color: color,
            animate: _state == FrameonConnectionState.scanning ||
                _state == FrameonConnectionState.connecting,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontSize: 9, color: color,
            letterSpacing: 1.5, fontFamily: 'monospace',
          )),
          const Spacer(),
          Icon(icon, color: color.withValues(alpha: 0.5), size: 13),
          const SizedBox(width: 4),
          Text(
            _state == FrameonConnectionState.connected
                ? 'TAP TO DISCONNECT'
                : 'TAP TO CONNECT',
            style: TextStyle(
              fontSize: 8, color: color.withValues(alpha: 0.4),
              letterSpacing: 1, fontFamily: 'monospace',
            ),
          ),
        ]),
      ),
    );
  }

  (String, Color, IconData) _stateInfo(FrameonConnectionState state) {
    switch (state) {
      case FrameonConnectionState.disconnected:
        return ('NO DEVICE', const Color(0xFF444444), Icons.bluetooth_disabled);
      case FrameonConnectionState.scanning:
        return ('SCANNING...', const Color(0xFF00B4FF), Icons.bluetooth_searching);
      case FrameonConnectionState.connecting:
        return ('CONNECTING...', const Color(0xFFFFE600), Icons.bluetooth_searching);
      case FrameonConnectionState.connected:
        return ('FRAMEON CONNECTED', const Color(0xFF00FF41), Icons.bluetooth_connected);
      case FrameonConnectionState.error:
        return ('CONNECTION ERROR', const Color(0xFFFF2D2D), Icons.bluetooth_disabled);
    }
  }
}

// ── Device scanner bottom sheet ───────────────────────────────────────────────

class DeviceScannerSheet extends StatefulWidget {
  final BleManager manager;

  const DeviceScannerSheet({super.key, required this.manager});

  /// Shows the scanner sheet using the current theme's surface color.
  /// Previously this hardcoded a dark hex value, breaking light mode.
  static Future<void> show(BuildContext context, BleManager manager) {
    final colors = AppColors.of(context);
    return showModalBottomSheet(
      context: context,
      // ✅ Was: backgroundColor: const Color(0xFF0D0D1A)  ← hardcoded dark
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: colors.border),
      ),
      builder: (_) => DeviceScannerSheet(manager: manager),
    );
  }

  @override
  State<DeviceScannerSheet> createState() => _DeviceScannerSheetState();
}

class _DeviceScannerSheetState extends State<DeviceScannerSheet> {
  List<FrameonDevice> _devices = [];
  FrameonConnectionState _state = FrameonConnectionState.disconnected;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _state = widget.manager.state;
    _subs.add(widget.manager.connectionStateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(widget.manager.devicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    }));
    _subs.add(widget.manager.errorStream.listen((err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err, style: const TextStyle(fontFamily: 'monospace')),
        ));
      }
    }));
    _startScan();
  }

  @override
  void dispose() {
    for (final sub in _subs) sub.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    final granted = await widget.manager.requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth permissions required',
              style: TextStyle(fontFamily: 'monospace')),
        ));
      }
      return;
    }
    widget.manager.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 3,
              decoration: BoxDecoration(
                color: colors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(children: [
            Text('FIND DEVICE', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: colors.textPrimary,
              letterSpacing: 2, fontFamily: 'monospace',
            )),
            const Spacer(),
            if (_state == FrameonConnectionState.scanning)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  color: colors.accentBlue, strokeWidth: 1.5,
                ),
              )
            else
              GestureDetector(
                onTap: _startScan,
                child: Text('SCAN AGAIN', style: TextStyle(
                  fontSize: 10, color: colors.accentBlue,
                  letterSpacing: 1, fontFamily: 'monospace',
                )),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Looking for Frameon devices nearby...', style: TextStyle(
            fontSize: 10, color: colors.textMuted, fontFamily: 'monospace',
          )),
          const SizedBox(height: 20),

          // Device list
          if (_devices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Icon(Icons.bluetooth_searching, color: colors.textMuted, size: 32),
                const SizedBox(height: 12),
                Text(
                  _state == FrameonConnectionState.scanning
                      ? 'Scanning for devices...'
                      : 'No devices found',
                  style: TextStyle(fontSize: 11, color: colors.textMuted,
                      fontFamily: 'monospace'),
                ),
              ]),
            )
          else
            ...(_devices.map((d) => _DeviceTile(
              device: d,
              isConnected: widget.manager.connectedDeviceId == d.id,
              isConnecting: _state == FrameonConnectionState.connecting,
              colors: colors,
              onTap: () async {
                if (widget.manager.connectedDeviceId == d.id) {
                  await widget.manager.disconnect();
                } else {
                  await widget.manager.connect(d);
                  if (mounted) Navigator.pop(context);
                }
              },
            ))),

          const SizedBox(height: 20),

          // Disconnect button if connected
          if (_state == FrameonConnectionState.connected) ...[
            GestureDetector(
              onTap: () async {
                await widget.manager.disconnect();
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: colors.accentRed.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('DISCONNECT', textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11, color: colors.accentRed,
                    letterSpacing: 1.5, fontFamily: 'monospace',
                  )),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final FrameonDevice device;
  final bool isConnected;
  final bool isConnecting;
  final AppColors colors;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isConnected,
    required this.isConnecting,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? colors.accent : colors.accentBlue;

    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: color, size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold,
                  color: colors.textPrimary, fontFamily: 'monospace',
                )),
                Text(device.id, style: TextStyle(
                  fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
                )),
              ],
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(isConnected ? 'CONNECTED' : 'CONNECT',
              style: TextStyle(
                fontSize: 9, color: color,
                letterSpacing: 1, fontFamily: 'monospace',
              )),
            const SizedBox(height: 2),
            Text('${device.rssi} dBm', style: TextStyle(
              fontSize: 9, color: colors.textMuted, fontFamily: 'monospace',
            )),
          ]),
        ]),
      ),
    );
  }
}

// ── Transfer progress bar ─────────────────────────────────────────────────────

class TransferProgressBar extends StatelessWidget {
  final double progress;
  final String label;
  final Color color;

  const TransferProgressBar({
    super.key,
    required this.progress,
    this.label = '',
    this.color = const Color(0xFF00FF41),
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(
          fontSize: 9, color: color, fontFamily: 'monospace',
        )),
        const Spacer(),
        Text('${(progress * 100).round()}%', style: TextStyle(
          fontSize: 9, color: color.withValues(alpha: 0.6),
          fontFamily: 'monospace',
        )),
      ]),
      const SizedBox(height: 4),
      Stack(children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(
                color: color.withValues(alpha: 0.5), blurRadius: 4,
              )],
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ── Animated dot ──────────────────────────────────────────────────────────────

class _StateDot extends StatefulWidget {
  final Color color;
  final bool animate;
  const _StateDot({required this.color, required this.animate});

  @override
  State<_StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<_StateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StateDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animate) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(
              alpha: widget.animate ? 0.4 + _ctrl.value * 0.6 : 1.0),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: widget.color.withValues(alpha: 0.4),
            blurRadius: 4,
          )],
        ),
      ),
    );
  }
}