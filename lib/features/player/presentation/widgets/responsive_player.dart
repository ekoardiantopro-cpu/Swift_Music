import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../../library/presentation/library_cubit.dart';
import '../artwork_style_cubit.dart';
import '../player_cubit.dart';
import 'album_stage.dart';
import '../../../personal/presentation/personal_cubit.dart';

/// Uses safe viewport constraints rather than device names or fixed heights.
class ResponsivePlayer extends StatelessWidget {
  const ResponsivePlayer({
    super.key,
    required this.state,
    required this.lyrics,
    required this.position,
    required this.maximum,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolume,
    required this.onArtwork,
    required this.onDevices,
    required this.onQueue,
    this.onSleepTimer,
    this.onLock,
  });
  final PlayerState state;
  final String lyrics;
  final double position;
  final double maximum;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onVolume;
  final VoidCallback onArtwork;
  final VoidCallback onDevices;
  final VoidCallback onQueue;
  final VoidCallback? onSleepTimer;
  final VoidCallback? onLock;
  String _time(Duration duration) {
    final seconds = math.max(0, duration.inSeconds);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _header(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Tutup player',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          key: const Key('volume-trigger'),
          tooltip: 'Atur volume',
          onPressed: onVolume,
          icon: MotionIcon(
            state.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        const Expanded(
          child: Text(
            'Swift Music',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Antrean',
          onPressed: onQueue,
          icon: const Icon(Icons.queue_music),
        ),
      ],
    ),
  );
  Widget _artwork(BuildContext context, double size) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedScale(
        scale: state.playing ? 1 : .97,
        duration: motionDuration(context, 420),
        curve: Curves.easeOutCubic,
        child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
          builder: (context, selection) => Hero(
            tag: 'player-artwork',
            child: AlbumStage(
              onNext: () => context.read<ArtworkStyleCubit>().next(),
              onDoubleTap:
                  state.item?.extras?['network'] != true &&
                      PersonalScope.maybeOf(context) != null &&
                      PersonalScope.maybeOf(
                            context,
                          )!.state.settings['gestures'] !=
                          false
                  ? () =>
                        context.read<LibraryCubit>().toggleLike(state.item!.id)
                  : null,
              onSwipeNext:
                  PersonalScope.maybeOf(context) != null &&
                      PersonalScope.maybeOf(
                            context,
                          )!.state.settings['gestures'] !=
                          false
                  ? context.read<PlayerCubit>().next
                  : null,
              onSwipePrevious: context.read<PlayerCubit>().previous,
              trackId: state.item!.id,
              title: state.item!.title,
              lyrics: lyrics,
              volume: state.volume,
              url: state.item!.artUri?.toString() ?? '',
              style: selection.style,
              playing: state.playing,
              position: state.position,
              onSeek: context.read<PlayerCubit>().seek,
              size: size,
            ),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
          builder: (context, selection) => TextButton.icon(
            onPressed: onArtwork,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(
              'Tampilan album · ${selection.style.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _metadata(BuildContext context, bool compact) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: state.item!.title,
              child: Text(
                state.item!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              state.item!.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppTheme.secondary),
            ),
          ],
        ),
      ),
      BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, library) => IconButton(
          tooltip: library.likes.contains(state.item!.id)
              ? 'Hapus favorit'
              : 'Sukai lagu',
          onPressed: state.item?.extras?['network'] == true
              ? null
              : () => context.read<LibraryCubit>().toggleLike(state.item!.id),
          icon: MotionIcon(
            library.likes.contains(state.item!.id)
                ? Icons.favorite
                : Icons.favorite_border,
            color: library.likes.contains(state.item!.id)
                ? AppTheme.green
                : Colors.white,
          ),
        ),
      ),
    ],
  );
  Widget _timeline(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 40,
        child: Slider(
          key: const Key('seek-slider'),
          value: position,
          max: maximum,
          semanticFormatterCallback: (value) =>
              _time(Duration(milliseconds: value.round())),
          onChangeStart: state.duration > Duration.zero ? onSeekStart : null,
          onChanged: state.duration > Duration.zero ? onSeekChanged : null,
          onChangeEnd: state.duration > Duration.zero ? onSeekEnd : null,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _time(Duration(milliseconds: position.round())),
            style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
          ),
          Text(
            _time(state.duration),
            style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
          ),
        ],
      ),
    ],
  );
  Widget _transport(BuildContext context, bool compact) {
    final player = context.read<PlayerCubit>();
    return SizedBox(
      key: const Key('transport-controls'),
      height: compact ? 60 : 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            child: IconButton(
              tooltip: 'Shuffle',
              onPressed: player.toggleShuffle,
              icon: MotionIcon(
                Icons.shuffle,
                color: state.shuffle ? AppTheme.green : AppTheme.secondary,
              ),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Previous',
              onPressed: player.previous,
              icon: const Icon(Icons.skip_previous_rounded, size: 30),
            ),
          ),
          SizedBox.square(
            dimension: compact ? 60 : 72,
            child: PressScale(
              child: FilledButton(
                key: const Key('main-play-button'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                onPressed: state.loading ? null : player.togglePlay,
                child: state.loading
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : MotionIcon(
                        state.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
              ),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Next',
              onPressed: player.next,
              icon: const Icon(Icons.skip_next_rounded, size: 30),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Repeat: ${state.repeat.name}',
              onPressed: player.cycleRepeat,
              icon: MotionIcon(
                state.repeat == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: state.repeat == AudioServiceRepeatMode.none
                    ? AppTheme.secondary
                    : AppTheme.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _devices() => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onDevices,
              icon: const Icon(Icons.devices, size: 18),
              label: const Text(
                'This device · Demo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (onLock != null)
          IconButton(
            tooltip: 'Kunci sentuhan',
            onPressed: onLock,
            icon: const Icon(Icons.lock_outline),
          ),
        IconButton(
          tooltip: 'Sleep timer',
          onPressed: onSleepTimer,
          icon: Icon(
            state.sleepActive ? Icons.bedtime : Icons.bedtime_outlined,
            color: state.sleepActive ? AppTheme.green : AppTheme.secondary,
          ),
        ),
      ],
    ),
  );
  List<Widget> _controls(BuildContext context, bool compact) => [
    _metadata(context, compact),
    const SizedBox(height: 6),
    EqualizerVisualizer(
      playing: state.playing,
      volume: state.volume,
      height: compact ? 20 : 28,
    ),
    _timeline(context),
    const SizedBox(height: 8),
    _transport(context, compact),
    const SizedBox(height: 6),
    _devices(),
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final wide =
          viewport.maxWidth >= 760 ||
          (viewport.maxWidth >= 480 && viewport.maxWidth > viewport.maxHeight);
      final compact = viewport.maxHeight < 760;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final horizontal = viewport.maxWidth < 360 ? 16.0 : 24.0;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
            child: LayoutBuilder(
              builder: (context, available) {
                if (wide) {
                  final stageSize = math.max(
                    128.0,
                    math.min(
                      420.0,
                      math.min(
                        (available.maxWidth - 24) * .46,
                        available.maxHeight - 100,
                      ),
                    ),
                  );
                  return Column(
                    children: [
                      _header(context),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Center(
                                  child: _artwork(context, stageSize),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, panel) =>
                                    SingleChildScrollView(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: panel.maxHeight,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: _controls(context, true),
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                // Large accessibility text gets a scroll fallback instead of clipping.
                final reserved =
                    (compact ? 360.0 : 380.0) + math.max(0, scale - 1) * 150;
                // Accessibility text needs room for the lyric header and body.
                // Let the page scroll rather than shrinking lyrics out of view.
                final minimumStage = scale > 1.3 ? available.maxWidth : 128.0;
                final stageSize = math.min(
                  400.0,
                  math.min(
                    available.maxWidth,
                    math.max(minimumStage, available.maxHeight - reserved),
                  ),
                );
                return SingleChildScrollView(
                  key: const Key('player-scroll'),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: available.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _header(context),
                        const SizedBox(height: 8),
                        _artwork(context, stageSize),
                        const SizedBox(height: 8),
                        ..._controls(context, compact),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
