import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/domain/saved_music_folder.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../domain/music_playlist.dart';
import 'collection_screens.dart';
import 'playlist_cubit.dart';
import 'track_actions.dart';

class SavedFolderCard extends StatelessWidget {
  const SavedFolderCard({super.key, required this.folder});
  final SavedMusicFolder folder;
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>();
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              folder.error == null
                  ? Icons.folder_outlined
                  : Icons.folder_off_outlined,
            ),
            title: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              folder.error ?? '${folder.fingerprints.length} file dikenali',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Pindai ulang ${folder.name}',
                  icon: const Icon(Icons.refresh),
                  onPressed: catalog.state.importing
                      ? null
                      : () => catalog.rescanFolder(folder.id),
                ),
                IconButton(
                  tooltip: 'Lepas folder ${folder.name}',
                  icon: const Icon(Icons.link_off),
                  onPressed: catalog.state.importing
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Lepas sumber folder?'),
                              content: const Text(
                                'Salinan lagu di Library tetap ada. Pemindaian otomatis folder ini akan dihentikan.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Batal'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Lepas'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await catalog.forgetFolder(folder.id);
                          }
                        },
                ),
              ],
            ),
          ),
          SwitchListTile.adaptive(
            dense: true,
            title: const Text(
              'Deteksi lagu baru saat aplikasi aktif',
              style: TextStyle(fontSize: 12),
            ),
            value: folder.autoScan,
            onChanged: catalog.state.importing
                ? null
                : (value) => catalog.setAutoScan(folder.id, value),
          ),
        ],
      ),
    );
  }
}

class PlaylistsHeading extends StatelessWidget {
  const PlaylistsHeading({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'Playlist saya',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        tooltip: 'Buat playlist',
        icon: const Icon(Icons.playlist_add),
        onPressed: () async {
          final id = await createPlaylist(context);
          if (id != null && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => PlaylistScreen(id: id)),
            );
          }
        },
      ),
    ],
  );
}

class UserPlaylistCard extends StatelessWidget {
  const UserPlaylistCard({super.key, required this.playlist});
  final MusicPlaylist playlist;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.playlist_play, color: AppTheme.green),
    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${playlist.trackIds.length} lagu'),
    trailing: IconButton(
      tooltip: 'Putar playlist ${playlist.name}',
      icon: const Icon(Icons.play_circle_fill, color: AppTheme.green),
      onPressed: playlist.trackIds.isEmpty
          ? null
          : () => context.read<PlayerCubit>().playCollection(playlist.trackIds),
    ),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PlaylistScreen(id: playlist.id)),
    ),
  );
}

class LibrarySortButton extends StatelessWidget {
  const LibrarySortButton({super.key});
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlaylistCubit>();
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Urutkan lagu',
      initialValue: cubit.state.sort,
      onSelected: cubit.setSort,
      itemBuilder: (_) => LibrarySort.values
          .map((sort) => PopupMenuItem(value: sort, child: Text(sort.label)))
          .toList(),
      icon: const Icon(Icons.sort),
    );
  }
}
