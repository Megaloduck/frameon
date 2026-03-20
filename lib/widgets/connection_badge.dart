import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_state.dart';
import '../services/providers.dart';
import '../services/transport_service.dart';
import '../theme/app_theme.dart';

class ConnectionBadge extends ConsumerWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transport = ref.watch(activeTransportProvider);
    final status    = ref.watch(connectionStatusProvider);
    final state     = ref.watch(deviceStateProvider);

    final Color   color;
    final String  label;
    final IconData icon;

    switch (transport) {
      case ActiveTransport.usb:
        color = AppColors.accent;
        label = 'USB';
        icon  = Icons.usb;
      case ActiveTransport.wifi:
        color = AppColors.connected;
        label = state.deviceIp ?? 'Wi-Fi';
        icon  = Icons.wifi;
      case ActiveTransport.none:
        color = switch (status) {
          ConnectionStatus.connecting    => AppColors.connecting,
          ConnectionStatus.connected     => AppColors.connected,
          ConnectionStatus.disconnected  => AppColors.disconnected,
        };
        label = switch (status) {
          ConnectionStatus.connecting    => 'Connecting…',
          ConnectionStatus.connected     => state.deviceIp ?? 'Connected',
          ConnectionStatus.disconnected  => 'No device',
        };
        icon = Icons.link_off;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PulseDot(color: color, pulse: status == ConnectionStatus.connecting),
        const SizedBox(width: 5),
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
              color: color, fontSize: 12,
              fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _PulseDot({required this.color, required this.pulse});
  @override State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 7, height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle));
    if (!widget.pulse) return dot;
    return AnimatedBuilder(animation: _anim,
        builder: (_, __) => Opacity(opacity: _anim.value, child: dot));
  }
}
