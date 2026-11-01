import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../../core/widgets/motion.dart';
import '../artwork_style_cubit.dart';
import 'neon_visualizer.dart';

/// Animation is visual only: it never seeks, restarts or alters the audio.
class AlbumDisplay extends StatefulWidget {
  const AlbumDisplay({
    super.key,
    required this.url,
    required this.size,
    required this.style,
    required this.playing,
    this.volume = 1,
  });
  final String url;
  final double size;
  final ArtworkStyle style;
  final bool playing;
  final double volume;
  @override
  State<AlbumDisplay> createState() => _AlbumDisplayState();
}

class _AlbumDisplayState extends State<AlbumDisplay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _neon = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _sync() {
    final active =
        widget.playing &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        fullMotionAllowed(context);
    if (active && widget.style == ArtworkStyle.vinyl) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
    if (active && widget.style == ArtworkStyle.pulse) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
    if (active &&
        widget.volume > 0 &&
        (widget.style == ArtworkStyle.spectrum ||
            widget.style == ArtworkStyle.wave)) {
      if (!_neon.isAnimating) _neon.repeat();
    } else {
      _neon.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AlbumDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    _pulse.dispose();
    _neon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = !fullMotionAllowed(context);
    return Semantics(
      label: 'Tampilan album ${widget.style.label}',
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: switch (widget.style) {
            ArtworkStyle.lyrics => const SizedBox.shrink(),
            ArtworkStyle.spectrum || ArtworkStyle.wave => NeonVisualizer(
              clock: _neon,
              circular: widget.style == ArtworkStyle.spectrum,
              volume: widget.volume,
              active: widget.playing && !reduced,
              size: widget.size,
            ),
            ArtworkStyle.cover => Artwork(
              url: widget.url,
              size: widget.size,
              radius: 28,
            ),
            ArtworkStyle.vinyl => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RotationTransition(
                    turns: reduced
                        ? const AlwaysStoppedAnimation(0)
                        : _rotation,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _VinylPainter()),
                        ),
                        Container(
                          width: widget.size * .44,
                          height: widget.size * .44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.green.withValues(alpha: .65),
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: Artwork(
                              url: widget.url,
                              size: widget.size * .44,
                              radius: widget.size,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                ),
              ],
            ),
            ArtworkStyle.pulse => AnimatedBuilder(
              animation: _pulse,
              child: Artwork(url: widget.url, size: widget.size, radius: 28),
              builder: (context, child) {
                final value = reduced || !widget.playing
                    ? 0.0
                    : Curves.easeInOut.transform(_pulse.value);
                return Transform.scale(
                  scale: .96 + .04 * value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.purple.withValues(
                            alpha: .18 + .2 * value,
                          ),
                          blurRadius: 20 + 25 * value,
                          spreadRadius: 2 + 5 * value,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              },
            ),
          },
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xFF333338),
            Color(0xFF09090D),
            Color(0xFF24242A),
            Color(0xFF08080B),
          ],
          stops: [0, .3, .8, 1],
        ).createShader(Offset.zero & size),
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .09);
    for (var ring = .26; ring < .98; ring += .025) {
      canvas.drawCircle(center, radius * ring, groove);
    }
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * .045
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .13);
    for (final angle in [-math.pi / 3, math.pi * .65]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * .78),
        angle,
        .48,
        false,
        shine,
      );
    }
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}
