import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion values, after the apple-design and emil-design-eng skills: quick ease-out for
/// things that enter, a faster exit, nothing over ~300 ms, and no motion at all when the
/// device asks for less (`MediaQuery.disableAnimations`).
abstract final class Motion {
  /// A pressed card or button: subtle, never smaller than 0.95.
  static const pressScale = 0.97;
  static const press = Duration(milliseconds: 110);
  static const release = Duration(milliseconds: 160);

  /// Strong ease-out (cubic-bezier(0.23, 1, 0.32, 1)): moves at once, settles softly.
  static const easeOut = Cubic(0.23, 1, 0.32, 1);

  /// The iOS sheet curve (cubic-bezier(0.32, 0.72, 0, 1)).
  static const drawer = Cubic(0.32, 0.72, 0, 1);

  static const sheetIn = Duration(milliseconds: 320);
  static const sheetOut = Duration(milliseconds: 220);
  static const windowIn = Duration(milliseconds: 220);
  static const windowOut = Duration(milliseconds: 150);

  /// Whether the person asked their device for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Shrinks its child a little while a finger or the mouse is down on it, so a tap
/// feels heard at once. Taps still go to the child; this only listens.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.enabled && !Motion.reduced(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: pressed ? Motion.pressScale : 1,
        duration: pressed ? Motion.press : Motion.release,
        curve: Motion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Plays an entering animation while [visible] and an exiting one before it lets its
/// child go, so things don't pop in and out of existence. The child is built with the
/// running animation (0 = gone, 1 = shown); [controllerOf] hands the controller out for
/// gestures that move it by hand (a sheet dragged down).
class AnimatedPresence extends StatefulWidget {
  const AnimatedPresence({
    super.key,
    required this.visible,
    required this.enter,
    required this.exit,
    required this.builder,
  });
  final bool visible;
  final Duration enter;
  final Duration exit;
  final Widget Function(BuildContext context, AnimationController animation)
  builder;
  @override
  State<AnimatedPresence> createState() => _AnimatedPresenceState();
}

class _AnimatedPresenceState extends State<AnimatedPresence>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.enter,
    reverseDuration: widget.exit,
  )..addStatusListener((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    }
  }

  void _show() {
    if (!mounted) return;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _hide() {
    if (Motion.reduced(context)) {
      _controller.value = 0;
    } else {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(AnimatedPresence old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _show();
    if (!widget.visible && old.visible) _hide();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context) && widget.visible && _controller.value == 0) {
      _controller.value = 1;
    }
    final gone = !widget.visible && _controller.isDismissed;
    if (gone) return const SizedBox.shrink();
    return widget.builder(context, _controller);
  }
}

/// Three dots that rise in turn while the assistant thinks; one label for screen readers.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, required this.label, this.color});
  final String label;
  final Color? color;
  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? DefaultTextStyle.of(context).style.color ?? Colors.grey;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: SizedBox(
        height: 20,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Transform.translate(
                  offset: Offset(0, -4 * _lift(_controller.value, i)),
                  child: Opacity(
                    opacity: 0.45 + 0.55 * _lift(_controller.value, i),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// How high dot [i] is at time [t]: each rises and falls in its own third.
  static double _lift(double t, int i) {
    final local = (t - i * 0.18) % 1.0;
    if (local > 0.5) return 0;
    return math.sin(local / 0.5 * math.pi);
  }
}

/// Gives an icon a small press-in and pop when it turns on (save, "me too"); with
/// [burst], short lines spray out as it lands. Nothing happens when it turns off.
class PopOnToggle extends StatefulWidget {
  const PopOnToggle({
    super.key,
    required this.on,
    required this.child,
    this.burst = false,
    this.burstColor,
  });
  final bool on;
  final Widget child;
  final bool burst;
  final Color? burstColor;
  @override
  State<PopOnToggle> createState() => _PopOnToggleState();
}

class _PopOnToggleState extends State<PopOnToggle>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.82,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.82,
        end: 1.18,
      ).chain(CurveTween(curve: Motion.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.18,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 40,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(PopOnToggle old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.burstColor ?? IconTheme.of(context).color ?? Colors.amber;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final running = _controller.isAnimating;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.burst && running && _controller.value > 0.25)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('pop-burst'),
                    painter: _BurstPainter(
                      progress: ((_controller.value - 0.25) / 0.75).clamp(0, 1),
                      color: color,
                    ),
                  ),
                ),
              ),
            ScaleTransition(
              key: const Key('pop-scale'),
              scale: running ? _scale : const AlwaysStoppedAnimation(1),
              child: child,
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Six short lines that fly out from the icon's edge and fade.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final eased = Motion.easeOut.transform(progress);
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress) * 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final start = radius * (0.55 + 0.35 * eased);
      final end = start + 5 * (1 - progress) + 2;
      canvas.drawLine(
        center + direction * start,
        center + direction * end,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
