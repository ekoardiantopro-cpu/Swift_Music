import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/library/presentation/track_actions.dart';
import '../../features/catalog/domain/track.dart';
import '../../features/library/presentation/library_cubit.dart';
import '../../features/player/presentation/player_cubit.dart';
import '../theme/app_theme.dart';
import 'artwork.dart';
import 'motion.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track});
  final Track track;
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (before, after) => before.item?.id != after.item?.id,
    builder: (context, player) => PressScale(
      child: AnimatedContainer(
        duration: motionDuration(context),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: player.item?.id == track.id
              ? AppTheme.green.withValues(alpha: .09)
              : Colors.transparent,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            leading: Artwork(url: track.artUrl, size: 52, radius: 10),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: player.item?.id == track.id
                    ? AppTheme.green
                    : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
            ),
            trailing: BlocBuilder<LibraryCubit, LibraryState>(
              builder: (context, state) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: state.likes.contains(track.id)
                        ? 'Hapus favorit'
                        : 'Sukai lagu',
                    icon: MotionIcon(
                      state.likes.contains(track.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: state.likes.contains(track.id)
                          ? AppTheme.green
                          : AppTheme.secondary,
                    ),
                    onPressed: () =>
                        context.read<LibraryCubit>().toggleLike(track.id),
                  ),
                  IconButton(
                    tooltip: 'Menu lagu ${track.title}',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () => showTrackActions(context, track),
                  ),
                ],
              ),
            ),
            onLongPress: () => showTrackActions(context, track),
            onTap: () => context.read<PlayerCubit>().playId(track.id),
          ),
        ),
      ),
    ),
  );
}
