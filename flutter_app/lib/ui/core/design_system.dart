import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../view_models/bridge_view_model.dart';

abstract final class Palette {
  static const paper = Color(0xFFF4EEE0),
      high = Color(0xFFFBF6EA),
      oat = Color(0xFFE4D8BE),
      edge = Color(0xFFD6C6A6),
      ink = Color(0xFF39362E),
      muted = Color(0xFF6E6656),
      moss = Color(0xFF4C5540),
      paleMoss = Color(0xFFDEE1CE),
      slate = Color(0xFFDAE0E0),
      brick = Color(0xFF9E5B4A),
      brickDeep = Color(0xFF79392E),
      ochre = Color(0xFFEFE1C3);
}

class BridgeScope extends InheritedNotifier<BridgeViewModel> {
  const BridgeScope({
    super.key,
    required BridgeViewModel viewModel,
    required super.child,
  }) : super(notifier: viewModel);
  static BridgeViewModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BridgeScope>()!.notifier!;
}

ThemeData bridgeTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: Palette.paper,
  fontFamily: 'Spectral',
  fontFamilyFallback: const ['NotoSerifTC'],
  colorScheme: ColorScheme.fromSeed(
    seedColor: Palette.moss,
    surface: Palette.high,
    onSurface: Palette.ink,
    primary: Palette.moss,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 16, height: 1.6),
    bodyMedium: TextStyle(fontSize: 16, height: 1.6),
    bodySmall: TextStyle(fontSize: 13, height: 1.5),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      backgroundColor: Palette.moss,
      foregroundColor: Palette.high,
      shape: const RoundedRectangleBorder(),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Palette.brickDeep,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: const RoundedRectangleBorder(),
      side: const BorderSide(color: Palette.edge),
    ),
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: Palette.oat,
    selectedColor: Palette.paleMoss,
    side: BorderSide.none,
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    shape: RoundedRectangleBorder(),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: Palette.high,
    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Palette.brick, width: 2),
      borderRadius: BorderRadius.zero,
    ),
  ),
);
TextStyle displayStyle(double size) => TextStyle(
  fontFamily: 'YoungSerif',
  fontFamilyFallback: const ['NotoSerifTC'],
  fontSize: size,
  height: 1.3,
  color: Palette.ink,
);

class InkIcon extends StatelessWidget {
  const InkIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = Palette.ink,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _GrainPainter(), child: child);
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.paper);
    final paint = Paint()
      ..color = Palette.muted.withValues(alpha: .055)
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 3.5) {
      canvas.drawLine(Offset(x, 0), Offset(x + 12, size.height), paint);
    }
    final random = math.Random(42);
    for (int i = 0; i < 1600; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * .7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

class TornEdge extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()..moveTo(0, 3);
    for (double x = 0; x <= size.width; x += 8) {
      p.lineTo(x, 2 + math.sin(x * .7) * 1.5);
    }
    p.lineTo(size.width, size.height - 3);
    for (double x = size.width; x >= 0; x -= 8) {
      p.lineTo(x, size.height - 2 - math.sin(x * .6) * 1.5);
    }
    return p
      ..lineTo(0, 3)
      ..close();
  }

  @override
  bool shouldReclip(TornEdge old) => false;
}

class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.color = Palette.high,
    this.tape = false,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final Color color;
  final bool tape;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: tape ? 14 : 0, bottom: 8, right: 5),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          left: 4,
          top: 6,
          right: -4,
          bottom: -6,
          child: ClipPath(
            clipper: TornEdge(),
            child: const ColoredBox(color: Palette.edge),
          ),
        ),
        ClipPath(
          clipper: TornEdge(),
          child: Material(
            color: color,
            child: Padding(padding: padding, child: child),
          ),
        ),
        if (tape)
          Positioned(
            top: -9,
            left: 24,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -.24,
                child: CustomPaint(
                  size: const Size(80, 25),
                  painter: _TapePainter(color == Palette.slate),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.gingham);
  final bool gingham;
  @override
  void paint(Canvas canvas, Size size) {
    final color = gingham ? Palette.brick : const Color(0xFF7E93A0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: .6),
    );
    for (double x = 0; x < size.width; x += 12) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 6, size.height),
        Paint()..color = Palette.high.withValues(alpha: .28),
      );
    }
    if (gingham) {
      for (double y = 0; y < size.height; y += 12) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, 6),
          Paint()..color = Palette.high.withValues(alpha: .3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TapePainter old) => old.gingham != gingham;
}

class PaperHeading extends StatelessWidget {
  const PaperHeading(this.title, {super.key, this.badge});
  final String title;
  final String? badge;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'CourierPrime',
            fontFamilyFallback: ['NotoSerifTC'],
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        if (badge != null) PaperTag(badge!),
      ],
    ),
  );
}

class PaperTag extends StatelessWidget {
  const PaperTag(this.text, {super.key, this.color = Palette.oat});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, height: 1.4, color: Palette.muted),
    ),
  );
}

class FlowBody extends StatelessWidget {
  const FlowBody({super.key, required this.children, this.maxWidth = 760});
  final List<Widget> children;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class RingIcon extends StatelessWidget {
  const RingIcon(this.name, {super.key, required this.selected});
  final String name;
  final bool selected;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: selected ? const _RingPainter() : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: InkIcon(name),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Paint()
        ..color = Palette.brick
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}
