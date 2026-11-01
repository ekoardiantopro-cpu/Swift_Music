import 'package:flutter/material.dart';
import '../../../core/widgets/motion.dart';

enum MusicSource { network, youtube, spotify }

extension MusicSourceLabel on MusicSource {
  String get label => switch (this) {
    MusicSource.network => 'Open Stream',
    MusicSource.youtube => 'YouTube Music',
    MusicSource.spotify => 'Spotify',
  };
}

class SourceIcon extends StatelessWidget {
  const SourceIcon(
    this.source, {
    super.key,
    this.size = 30,
    this.selected = false,
  });
  final MusicSource source;
  final double size;
  final bool selected;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: selected && fullMotionAllowed(context) ? 1.08 : 1,
    duration: motionDuration(context, 260),
    curve: Curves.easeOutCubic,
    child: AnimatedRotation(
      turns: selected && fullMotionAllowed(context) ? -.025 : 0,
      duration: motionDuration(context, 320),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _Logo(source)),
      ),
    ),
  );
}

class _Logo extends CustomPainter {
  _Logo(this.source);
  final MusicSource source;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final paint = Paint();
    if (source == MusicSource.spotify) {
      canvas.drawCircle(
        const Offset(16, 16),
        15,
        paint..color = const Color(0xFF1DB954),
      );
      paint
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        paint.strokeWidth = 2.5 - i * .35;
        canvas.drawPath(
          Path()
            ..moveTo(8.0 + i, 11.0 + i * 5)
            ..quadraticBezierTo(17, 7.0 + i * 5, 25.0 - i, 13.0 + i * 4),
          paint,
        );
      }
    } else if (source == MusicSource.youtube) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(1, 5, 30, 22),
          const Radius.circular(6),
        ),
        paint..color = const Color(0xFFFF0033),
      );
      canvas.drawPath(
        Path()
          ..moveTo(13, 10)
          ..lineTo(23, 16)
          ..lineTo(13, 22)
          ..close(),
        paint..color = Colors.white,
      );
    } else {
      paint
        ..color = const Color(0xFF52C7F2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(const Offset(16, 16), 14, paint);
      canvas.drawOval(const Rect.fromLTWH(9, 2, 14, 28), paint);
      canvas.drawLine(const Offset(3, 11), const Offset(29, 11), paint);
      canvas.drawLine(const Offset(3, 21), const Offset(29, 21), paint);
    }
  }

  @override
  bool shouldRepaint(_Logo oldDelegate) => oldDelegate.source != source;
}
