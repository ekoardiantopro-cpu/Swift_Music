import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../features/catalog/domain/catalog_repository.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../player_cubit.dart';
import '../now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.localOnly = false});
  final bool localOnly;
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) {
      final item = state.item;
      if (item == null) return const SizedBox.shrink();
      if (localOnly) {
        final url = item.extras?['url'];
        final tracks = context.read<CatalogRepository>().tracks;
        final localTrack = tracks.where((track) => track.id == item.id).firstOrNull;
        final isPlayingLocal =
            state.playing &&
            url is String &&
            Uri.tryParse(url)?.scheme == 'file' &&
            localTrack?.isLocal == true;
        if (!isPlayingLocal) return const SizedBox.shrink();
      }
      final total = state.duration.inMilliseconds;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: PressScale(
          child: Material(
            color: const Color(0xFF2A2437),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  fullscreenDialog: true,
                  transitionDuration: motionDuration(context, 380),
                  reverseTransitionDuration: motionDuration(context, 260),
                  pageBuilder: (_, animation, secondaryAnimation) =>
                      const NowPlayingScreen(),
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) =>
                          SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'player-artwork',
                          child: Artwork(
                            url: item.artUri?.toString() ?? '',
                            size: 44,
                            radius: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 20,
                          child: EqualizerVisualizer(
                            playing: state.playing,
                            volume: state.volume,
                            bars: 4,
                            height: 22,
                          ),
                        ),
                        if (state.loading)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: state.playing ? 'Pause' : 'Play',
                            onPressed: () =>
                                context.read<PlayerCubit>().togglePlay(),
                            icon: MotionIcon(
                              state.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Next',
                          onPressed: () => context.read<PlayerCubit>().next(),
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.white12,
                    value: total <= 0
                        ? 0
                        : (state.position.inMilliseconds / total)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
