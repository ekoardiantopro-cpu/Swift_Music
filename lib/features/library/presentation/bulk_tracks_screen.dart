import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import 'playlist_cubit.dart';
import 'library_cubit.dart';

class BulkTracksScreen extends StatefulWidget {
  const BulkTracksScreen({super.key});
  @override
  State<BulkTracksScreen> createState() => _BulkTracksScreenState();
}

class _BulkTracksScreenState extends State<BulkTracksScreen> {
  final _selected = <String>{};
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = context
        .watch<CatalogCubit>()
        .state
        .tracks
        .where(
          (t) => '${t.title} ${t.artist}'.toLowerCase().contains(
            _query.text.toLowerCase(),
          ),
        )
        .toList();
    final lists = context.watch<PlaylistCubit>();
    final player = context.read<PlayerCubit>();
    final library = context.read<LibraryCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text('${_selected.length} dipilih'),
        actions: [
          PopupMenuButton<String>(
            enabled: _selected.isNotEmpty,
            onSelected: (value) async {
              if (value == 'queue') {
                await player.enqueueMany(_selected.toList());
              } else if (value == 'next') {
                await player.enqueueMany(_selected.toList(), next: true);
              } else if (value == 'liked') {
                await library.mergeLikes(_selected);
              } else {
                final id = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in lists.state.playlists)
                          ListTile(
                            title: Text(p.name),
                            onTap: () => Navigator.pop(context, p.id),
                          ),
                      ],
                    ),
                  ),
                );
                if (id != null) {
                  final p = lists.state.playlists
                      .where((p) => p.id == id)
                      .firstOrNull;
                  if (p != null) {
                    await lists.setTracks(id, [...p.trackIds, ..._selected]);
                  }
                }
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${_selected.length} lagu diproses.')),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'queue',
                child: Text('Tambahkan ke antrean'),
              ),
              PopupMenuItem(value: 'next', child: Text('Putar berikutnya')),
              PopupMenuItem(value: 'liked', child: Text('Tambahkan favorit')),
              PopupMenuItem(
                value: 'playlist',
                child: Text('Tambahkan ke playlist'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Judul atau artis',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _selected.addAll(tracks.map((t) => t.id))),
                child: const Text('Pilih semua hasil'),
              ),
              TextButton(
                onPressed: () => setState(_selected.clear),
                child: const Text('Kosongkan pilihan'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => CheckboxListTile(
                title: Text(
                  tracks[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(tracks[i].artist),
                value: _selected.contains(tracks[i].id),
                onChanged: (value) => setState(() {
                  value == true
                      ? _selected.add(tracks[i].id)
                      : _selected.remove(tracks[i].id);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
