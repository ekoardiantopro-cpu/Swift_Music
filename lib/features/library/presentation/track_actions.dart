import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import 'playlist_cubit.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../personal/presentation/song_details_screen.dart';

Future<String?> editPlaylistName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(initial: initial),
    );

Future<String?> createPlaylist(BuildContext context) async {
  final cubit = context.read<PlaylistCubit>();
  final name = await editPlaylistName(context);
  return name == null ? null : cubit.create(name);
}

Future<void> addToPlaylist(BuildContext context, Track track) async {
  final playlists = context.read<PlaylistCubit>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: BlocBuilder<PlaylistCubit, PlaylistState>(
        bloc: playlists,
        builder: (context, state) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Tambahkan ke playlist',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Playlist baru'),
              onTap: () async {
                final name = await editPlaylistName(sheetContext);
                if (name == null) return;
                final id = await playlists.create(name);
                if (id != null) await playlists.addTrack(id, track.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            for (final list in state.playlists)
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(list.name),
                trailing: list.trackIds.contains(track.id)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () async {
                  await playlists.addTrack(list.id, track.id);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showTrackActions(BuildContext context, Track track) async {
  final catalog = context.read<CatalogCubit>();
  final player = context.read<PlayerCubit>();
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(track.artist),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Tambahkan ke playlist'),
            onTap: () => Navigator.pop(context, 'playlist'),
          ),
          if (PersonalScope.maybeOf(context) != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Detail, penanda dan catatan'),
              onTap: () => Navigator.pop(context, 'details'),
            ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Tambahkan ke antrean'),
            onTap: () => Navigator.pop(context, 'queue'),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('Putar berikutnya'),
            onTap: () => Navigator.pop(context, 'next'),
          ),
          if (track.isLocal && catalog.canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus dari Library'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'details') {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SongDetailsScreen(track: track)),
    );
    return;
  }
  if (action == 'playlist') {
    await addToPlaylist(context, track);
  }
  if (action == 'queue') {
    await player.enqueue(track.id);
  }
  if (action == 'next') await player.enqueueMany([track.id], next: true);
  if (action == 'delete') {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus dari Library?'),
        content: Text(
          'Salinan “${track.title}” di aplikasi akan dihapus. File asli di folder Anda tetap ada. '
          'Lagu ini juga dikeluarkan dari playlist dan antrean. Pilih folder lagi untuk mengimpornya kembali.',
        ),
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
    if (confirmed == true) await catalog.removeLocalTrack(track.id);
  }
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.initial});
  final String initial;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial.isEmpty ? 'Buat playlist' : 'Ubah nama playlist',
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Nama playlist'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}
