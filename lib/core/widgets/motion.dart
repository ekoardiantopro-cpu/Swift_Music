import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../features/personal/presentation/personal_cubit.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 280]) {
  final mode =
      PersonalScope.maybeOf(context)?.state.text('motion', 'full') ?? 'full';
  return MediaQuery.disableAnimationsOf(context) || mode == 'off'
      ? Duration.zero
      : Duration(
          milliseconds: mode == 'reduced'
              ? math.min(120, milliseconds)
              : milliseconds,
        );
}

bool fullMotionAllowed(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    (PersonalScope.maybeOf(context)?.state.text('motion', 'full') ?? 'full') ==
        'full';

/// Pointer feedback without competing with scrolling or the child's tap action.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    onPointerMove: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed && fullMotionAllowed(context) ? .96 : 1,
      duration: motionDuration(context, 160),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class MotionIcon extends StatelessWidget {
  const MotionIcon(this.icon, {super.key, this.color, this.size});
  final IconData icon;
  final Color? color;
  final double? size;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, 220),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: animation,
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: Icon(icon, key: ValueKey((icon, color)), color: color, size: size),
  );
}

/// Decorative playback visualizer, not FFT analysis of the audio signal.
/// A repaint-only ticker stops on pause, reduced motion, hidden routes and sleep.
class EqualizerVisualizer extends StatefulWidget {
  const EqualizerVisualizer({
    super.key,
    required this.playing,
    this.volume = 1,
    this.bars = 32,
    this.height = 38,
  });
  final bool playing;
  final double volume;
  final int bars;
  final double height;
  @override
  State<EqualizerVisualizer> createState() => _EqualizerVisualizerState();
}

class _EqualizerVisualizerState extends State<EqualizerVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
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
        widget.volume > 0 &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        fullMotionAllowed(context);
    if (active && !_controller.isAnimating) _controller.repeat();
    if (!active) _controller.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerVisualizer oldWidget) {
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: CustomPaint(
          painter: _BarsPainter(
            _controller,
            widget.playing && fullMotionAllowed(context),
            widget.volume,
            widget.bars,
          ),
        ),
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.clock, this.playing, this.volume, this.bars)
    : super(repaint: clock);
  final Animation<double> clock;
  final bool playing;
  final double volume;
  final int bars;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1DB954), Color(0xFFABF582)],
      ).createShader(Offset.zero & size);
    final step = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final wave =
          .22 +
          .78 *
              (math.sin(clock.value * math.pi * 2 + i * .83) *
                      math.sin(clock.value * math.pi * 4 - i * .37))
                  .abs();
      final height = playing ? 3 + (size.height - 3) * volume * wave : 3.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * step,
            (size.height - height) / 2,
            step * .58,
            height,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.playing != playing ||
      old.volume != volume ||
      old.bars != bars ||
      old.clock != clock;
}
