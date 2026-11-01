import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/track_tile.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../domain/music_playlist.dart';
import 'playlist_cubit.dart';
import 'library_cubit.dart';
import 'track_actions.dart';
import 'playlist_tools_screen.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistCubit>();
    final playlist = playlists.state.playlists
        .where((list) => list.id == id)
        .firstOrNull;
    final catalog = context.watch<CatalogCubit>().state.tracks;
    final map = {for (final track in catalog) track.id: track};
    final tracks = (playlist?.trackIds ?? [])
        .map((id) => map[id])
        .whereType<Track>()
        .toList();
    final missing =
        playlist?.trackIds.where((id) => !map.containsKey(id)).toList() ??
        <String>[];
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist telah dihapus.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: 'Detail playlist',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PlaylistToolsScreen(id: id),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ubah nama playlist',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await editPlaylistName(
                context,
                initial: playlist.name,
              );
              if (name != null) await playlists.rename(id, name);
            },
          ),
          IconButton(
            tooltip: 'Hapus playlist',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Hapus playlist?'),
                  content: const Text('Lagu di Library tetap ada.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await playlists.delete(id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => context.read<PlayerCubit>().playCollection(
                            tracks.map((track) => track.id).toList(),
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Putar ${tracks.length} lagu'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Tambah lagu ke playlist',
                  icon: const Icon(Icons.add),
                  onPressed: () => _selectTracks(context, playlist),
                ),
              ],
            ),
          ),
          if (playlist.trackIds.length > tracks.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${playlist.trackIds.length - tracks.length} lagu belum ditemukan. Impor file musik yang sama untuk mencocokkannya kembali.',
              ),
            ),
          if (tracks.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Tambahkan lagu dari tombol + atau menu lagu.'),
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                itemCount: tracks.length,
                onReorderItem: (from, to) {
                  final ids = tracks.map((track) => track.id).toList();
                  final item = ids.removeAt(from);
                  ids.insert(to, item);
                  playlists.setTracks(id, ids);
                },
                itemBuilder: (context, index) => Row(
                  key: ValueKey(tracks[index].id),
                  children: [
                    Expanded(child: TrackTile(track: tracks[index])),
                    IconButton(
                      tooltip: 'Keluarkan dari playlist',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => playlists.setTracks(
                        id,
                        tracks
                            .where((track) => track.id != tracks[index].id)
                            .map((track) => track.id)
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (missing.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.builder(
                itemCount: missing.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.music_off_outlined),
                  title: Text(
                    playlist.trackLabels[missing[index]] ??
                        'Lagu belum tersedia',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text(
                    'Impor file musik yang sama untuk mencocokkan',
                  ),
                  trailing: IconButton(
                    tooltip: 'Keluarkan lagu yang belum tersedia',
                    icon: const Icon(Icons.close),
                    onPressed: () => playlists.setTracks(
                      id,
                      playlist.trackIds
                          .where((trackId) => trackId != missing[index])
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _selectTracks(BuildContext context, MusicPlaylist playlist) {
    final collections = context.read<PlaylistCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: BlocBuilder<PlaylistCubit, PlaylistState>(
            bloc: collections,
            builder: (context, state) {
              final selected = state.playlists
                  .where((list) => list.id == id)
                  .firstOrNull;
              final tracks = context.watch<CatalogCubit>().state.tracks;
              return ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) => CheckboxListTile(
                  title: Text(tracks[index].title),
                  subtitle: Text(tracks[index].artist),
                  value: selected?.trackIds.contains(tracks[index].id) ?? false,
                  onChanged: (checked) {
                    if (selected == null) return;
                    collections.setTracks(
                      id,
                      checked == true
                          ? [...selected.trackIds, tracks[index].id]
                          : selected.trackIds
                                .where((entry) => entry != tracks[index].id)
                                .toList(),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TrackCollectionScreen extends StatelessWidget {
  const TrackCollectionScreen({
    super.key,
    required this.title,
    this.artist,
    this.album,
    this.liked = false,
  });
  final String title;
  final String? artist;
  final String? album;
  final bool liked;
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state.tracks;
    final likes = context.watch<LibraryCubit>().state.likes;
    final playlists = context.watch<PlaylistCubit>();
    final tracks = playlists.sorted(
      catalog.where(
        (track) =>
            (artist == null || track.artist == artist) &&
            (album == null || track.album == album) &&
            (!liked || likes.contains(track.id)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => context.read<PlayerCubit>().playCollection(
                      tracks.map((track) => track.id).toList(),
                    ),
              icon: const Icon(Icons.play_arrow),
              label: Text('Putar ${tracks.length} lagu'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (_, index) => TrackTile(track: tracks[index]),
            ),
          ),
        ],
      ),
    );
  }
}
