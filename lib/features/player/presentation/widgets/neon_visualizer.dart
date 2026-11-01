import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Stylized motion, not FFT data. The owner stops the clock when hidden/paused.
class NeonVisualizer extends StatelessWidget {
  const NeonVisualizer({
    super.key,
    required this.clock,
    required this.circular,
    required this.volume,
    required this.active,
    required this.size,
  });
  final Animation<double> clock;
  final bool circular;
  final double volume;
  final bool active;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: ColoredBox(
      color: const Color(0xFF10071F),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _NeonPainter(clock, circular, volume, active),
              ),
            ),
            if (circular)
              SizedBox(
                width: size * .4,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SWIFT\nMUSIC',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NeonPainter extends CustomPainter {
  _NeonPainter(this.clock, this.circular, this.volume, this.active)
    : super(repaint: clock);
  final Animation<double> clock;
  final bool circular;
  final double volume;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    // The owner freezes the clock on pause: geometry stays at its last phase.
    final phase = clock.value * math.pi * 2;
    final gain = volume;
    final bounds = Offset.zero & size;
    final colors = [
      const Color(0xFF19E7ED),
      const Color(0xFF775BFF),
      const Color(0xFFFF359F),
    ];
    if (circular) {
      final center = size.center(Offset.zero);
      final radius = size.width * .29;
      final shader = SweepGradient(
        colors: [...colors, colors.first],
        transform: GradientRotation(phase),
      ).createShader(bounds);
      final paint = Paint()
        ..shader = shader
        ..strokeWidth = size.width * .008
        ..strokeCap = StrokeCap.round;
      final glow = Paint()
        ..shader = shader
        ..strokeWidth = size.width * .02
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      final bars = Path();
      for (var i = 0; i < 72; i++) {
        final angle = i / 72 * math.pi * 2;
        final envelope =
            .25 +
            .75 *
                (math.sin(angle * 5 + phase) * math.cos(angle * 3 - phase))
                    .abs();
        final length = size.width * (.015 + .13 * gain * envelope);
        final direction = Offset(math.cos(angle), math.sin(angle));
        final start = center + direction * radius;
        final end = center + direction * (radius + length);
        bars.moveTo(start.dx, start.dy);
        bars.lineTo(end.dx, end.dy);
      }
      // One glow pass for the whole ring rather than a blur per bar.
      canvas.drawPath(bars, glow);
      canvas.drawPath(bars, paint);
      canvas.drawCircle(
        center,
        radius - 8,
        Paint()
          ..color = colors.first.withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      _ribbons(canvas, size, phase, gain, colors);
    }
  }

  void _ribbons(
    Canvas canvas,
    Size size,
    double phase,
    double gain,
    List<Color> colors,
  ) {
    final shader = LinearGradient(
      colors: colors,
    ).createShader(Offset.zero & size);
    final baseline = size.height * .53;
    for (var layer = 0; layer < 3; layer++) {
      final upper = <Offset>[];
      final lower = <Offset>[];
      for (var i = 0; i <= 96; i++) {
        final t = i / 96;
        final envelope = math.sin(math.pi * t);
        final wave =
            math.sin(t * math.pi * 4 - phase + layer * .85) * .7 +
            math.sin(t * math.pi * 2 + phase + layer * .55) * .3;
        final amplitude =
            envelope * size.height * (.025 + .21 * gain) * (1 - layer * .16);
        final x = size.width * (.07 + .86 * t);
        upper.add(
          Offset(x, baseline + wave * amplitude - envelope * amplitude * .35),
        );
        lower.add(
          Offset(x, baseline + wave * amplitude + envelope * amplitude * .35),
        );
      }
      final ribbon = Path()..moveTo(upper.first.dx, upper.first.dy);
      for (final point in upper.skip(1)) {
        ribbon.lineTo(point.dx, point.dy);
      }
      for (final point in lower.reversed) {
        ribbon.lineTo(point.dx, point.dy);
      }
      ribbon.close();
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: .15 + layer * .055),
      );
      final edge = Path()..moveTo(upper.first.dx, upper.first.dy);
      for (final point in upper.skip(1)) {
        edge.lineTo(point.dx, point.dy);
      }
      if (layer == 1) {
        canvas.drawPath(
          edge,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawPath(
        edge,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: .75),
      );
    }
  }

  @override
  bool shouldRepaint(_NeonPainter old) =>
      old.circular != circular ||
      old.volume != volume ||
      old.active != active ||
      old.clock != clock;
}
