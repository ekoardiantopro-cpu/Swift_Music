import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../personal/data/personal_assets.dart';
import '../../personal/presentation/personal_dialogs.dart';
import 'playlist_cubit.dart';
import 'collection_screens.dart';
import '../../../core/widgets/artwork.dart';

class PlaylistToolsScreen extends StatelessWidget {
  const PlaylistToolsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlaylistCubit>();
    final playlist = cubit.state.playlists.where((p) => p.id == id).firstOrNull;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist tidak tersedia.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Detail playlist')),
      body: ListView(
        children: [
          if (playlist.cover.isNotEmpty)
            Center(child: Artwork(url: playlist.cover, size: 180, radius: 24)),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Deskripsi'),
            subtitle: Text(playlist.description),
            onTap: () async {
              final value = await askMusicText(
                context,
                'Deskripsi playlist',
                initial: playlist.description,
                maxLength: 2000,
              );
              if (value != null) await cubit.details(id, description: value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Folder playlist'),
            subtitle: Text(
              playlist.folder.isEmpty ? 'Tanpa folder' : playlist.folder,
            ),
            onTap: () async {
              final value = await askMusicText(
                context,
                'Nama folder',
                initial: playlist.folder,
                maxLength: 80,
              );
              if (value != null) await cubit.details(id, folder: value.trim());
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Pilih cover playlist'),
            onTap: () async {
              try {
                final uri = await context.read<PersonalAssets>().pickCover();
                if (uri != null) await cubit.details(id, cover: uri);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cover gagal dibaca.')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('Batalkan perubahan terakhir'),
            onTap: cubit.canUndo ? cubit.undo : null,
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_check),
            title: const Text('Ekspor M3U'),
            subtitle: const Text(
              'Letakkan M3U bersama file asli dengan nama yang sama',
            ),
            onTap: () async {
              final tracks = {
                for (final t in context.read<CatalogCubit>().state.tracks)
                  t.id: t,
              };
              final lines = <String>['#EXTM3U'];
              String safe(String text) =>
                  text.replaceAll(RegExp(r'[\r\n]'), ' ');
              for (final songId in playlist.trackIds) {
                final track = tracks[songId];
                if (track == null) continue;
                lines.add(
                  '#EXTINF:${track.duration?.inSeconds ?? -1},${safe(track.artist)} - ${safe(track.title)}',
                );
                if (!track.isLocal) {
                  lines.add(track.audioUrl);
                } else {
                  final extension = Uri.parse(
                    track.audioUrl,
                  ).path.split('.').last;
                  final original =
                      track.info['originalName'] as String? ??
                      '${track.title}.$extension';
                  lines.add(
                    './${safe(original.replaceAll('\\', '/').split('/').last)}',
                  );
                }
              }
              try {
                final uri = await FilePicker.saveFile(
                  fileName:
                      '${playlist.name.replaceAll(RegExp(r'[^\w -]'), '_')}.m3u8',
                  bytes: Uint8List.fromList(
                    utf8.encode('${lines.join('\n')}\n'),
                  ),
                  mimeType: 'audio/x-mpegurl',
                );
                if (uri != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'M3U tersimpan. Musik tidak disalin dalam ekspor ini.',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ekspor belum berhasil.')),
                  );
                }
              }
            },
          ),
          const ListTile(title: Text('Riwayat perubahan')),
          for (final event in playlist.changes)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text('${event['action'] ?? ''}'),
              subtitle: Text(
                event['at'] is int
                    ? DateTime.fromMillisecondsSinceEpoch(
                        event['at'] as int,
                      ).toLocal().toString().split('.').first
                    : '',
              ),
            ),
        ],
      ),
    );
  }
}

class PlaylistFoldersScreen extends StatelessWidget {
  const PlaylistFoldersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlaylistCubit>();
    final folders = cubit.state.playlists.map((p) => p.folder).toSet().toList()
      ..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folder playlist'),
        actions: [
          IconButton(
            tooltip: 'Gabungkan playlist',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MergePlaylistsScreen(),
              ),
            ),
            icon: const Icon(Icons.merge_type),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final folder in folders)
            ExpansionTile(
              title: Text(folder.isEmpty ? 'Tanpa folder' : folder),
              leading: const Icon(Icons.folder_outlined),
              children: [
                for (final playlist in cubit.state.playlists.where(
                  (p) => p.folder == folder,
                ))
                  ListTile(
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.trackIds.length} lagu'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistScreen(id: playlist.id),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class MergePlaylistsScreen extends StatefulWidget {
  const MergePlaylistsScreen({super.key});
  @override
  State<MergePlaylistsScreen> createState() => _MergePlaylistsScreenState();
}

class _MergePlaylistsScreenState extends State<MergePlaylistsScreen> {
  final _selected = <String>{};
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlaylistCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gabungkan playlist'),
        actions: [
          TextButton(
            onPressed: _selected.length < 2
                ? null
                : () async {
                    final name = await askMusicText(
                      context,
                      'Nama playlist gabungan',
                      maxLength: 80,
                    );
                    if (name == null) return;
                    final id = await cubit.mergePlaylists(
                      _selected.toList(),
                      name,
                    );
                    if (id != null && context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PlaylistScreen(id: id),
                        ),
                      );
                    }
                  },
            child: const Text('Gabung'),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final p in cubit.state.playlists)
            CheckboxListTile(
              title: Text(p.name),
              subtitle: Text('${p.trackIds.length} lagu'),
              value: _selected.contains(p.id),
              onChanged: (value) => setState(() {
                value == true ? _selected.add(p.id) : _selected.remove(p.id);
              }),
            ),
        ],
      ),
    );
  }
}
