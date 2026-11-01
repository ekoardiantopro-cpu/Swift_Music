import 'package:flutter/material.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/lyrics_awake.dart';
import '../artwork_style_cubit.dart';
import 'album_display.dart';
import 'lyrics_panel.dart';

class AlbumStage extends StatelessWidget {
  const AlbumStage({
    super.key,
    required this.style,
    required this.size,
    required this.trackId,
    required this.title,
    required this.url,
    required this.lyrics,
    required this.playing,
    required this.volume,
    required this.onNext,
    this.position = Duration.zero,
    this.onSeek,
    this.onDoubleTap,
    this.onSwipeNext,
    this.onSwipePrevious,
  });
  final ArtworkStyle style;
  final double size;
  final String trackId;
  final String title;
  final String url;
  final String lyrics;
  final bool playing;
  final double volume;
  final VoidCallback onNext;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onDoubleTap, onSwipeNext, onSwipePrevious;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Ganti tampilan album',
    hint: 'Ketuk untuk tampilan berikutnya. Sekarang ${style.label}',
    onTap: onNext,
    child: GestureDetector(
      key: const Key('album-stage'),
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: onNext,
      onDoubleTap: onDoubleTap,
      onHorizontalDragEnd: onSwipeNext == null
          ? null
          : (details) {
              if ((details.primaryVelocity ?? 0) < -150) onSwipeNext?.call();
              if ((details.primaryVelocity ?? 0) > 150) onSwipePrevious?.call();
            },
      child: LyricsAwake(
        lyrics: style == ArtworkStyle.lyrics,
        child: SizedBox.square(
          dimension: size,
          child: AnimatedSwitcher(
            duration: motionDuration(context, 420),
            reverseDuration: motionDuration(context, 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .94, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: TickerMode(
              key: ValueKey((style, trackId)),
              enabled: TickerMode.valuesOf(context).enabled,
              child: SizedBox.square(
                dimension: size,
                child: style == ArtworkStyle.lyrics
                    ? LyricsPanel(
                        trackId: trackId,
                        title: title,
                        fallback: lyrics,
                        position: position,
                        onSeek: onSeek,
                      )
                    : AlbumDisplay(
                        url: url,
                        size: size,
                        style: style,
                        playing: playing,
                        volume: volume,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
