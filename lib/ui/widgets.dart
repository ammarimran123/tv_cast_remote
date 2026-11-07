import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';

void haptic() {
  if (store.haptics) HapticFeedback.lightImpact();
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A round/rounded remote button. Fires once on press and, when [repeat] is
/// set, keeps firing while held (volume, D-pad).
class RemoteButton extends StatefulWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback onPressed;
  final bool repeat;
  final double size;
  final Color? color;
  final Color? foreground;
  final String? tooltip;
  final BorderRadius? radius;

  const RemoteButton({
    super.key,
    this.icon,
    this.label,
    required this.onPressed,
    this.repeat = false,
    this.size = 60,
    this.color,
    this.foreground,
    this.tooltip,
    this.radius,
  });

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  Timer? _delay;
  Timer? _repeat;
  bool _down = false;

  void _fire() {
    haptic();
    widget.onPressed();
  }

  void _start() {
    setState(() => _down = true);
    _fire();
    if (widget.repeat) {
      _delay = Timer(const Duration(milliseconds: 450), () {
        _repeat = Timer.periodic(
          const Duration(milliseconds: 130),
          (_) => _fire(),
        );
      });
    }
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        widget.color ??
        (dark ? const Color(0xFF232538) : const Color(0xFFECEAF6));
    final fg = widget.foreground ?? cs.onSurface;
    final child = AnimatedScale(
      scale: _down ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _down
              ? Color.alphaBlend(cs.primary.withValues(alpha: 0.25), bg)
              : bg,
          borderRadius: widget.radius ?? BorderRadius.circular(widget.size / 2),
        ),
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, color: fg, size: widget.size * 0.42)
            : Text(
                widget.label ?? '',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.size * 0.3,
                ),
              ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.tooltip ?? widget.label,
      child: Tooltip(
        message: widget.tooltip ?? '',
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _start(),
          onTapUp: (_) => _stop(),
          onTapCancel: _stop,
          child: child,
        ),
      ),
    );
  }
}

/// Shown on tabs that need a TV when none is connected.
class NotConnectedView extends StatelessWidget {
  final String message;
  final VoidCallback onFindDevices;
  const NotConnectedView({
    super.key,
    required this.message,
    required this.onFindDevices,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.connected_tv_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No TV connected',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onFindDevices,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Find my TV'),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
