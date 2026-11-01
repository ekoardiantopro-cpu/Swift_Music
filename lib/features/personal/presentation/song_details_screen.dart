import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../data/personal_assets.dart';
import 'personal_cubit.dart';
import 'personal_dialogs.dart';
import '../../../core/widgets/artwork.dart';

class SongDetailsScreen extends StatelessWidget {
  const SongDetailsScreen({super.key, required this.track});
  final Track track;
  @override
  Widget build(BuildContext context) {
    final scope = PersonalScope.maybeOf(context)!;
    final personal = scope.controller;
    final mark = scope.state.song(track.id);
    final song = personal.resolve(
      context
              .watch<CatalogCubit>()
              .state
              .tracks
              .where((t) => t.id == track.id)
              .firstOrNull ??
          track,
    );
    final player = context.watch<PlayerCubit>();
    String time(int ms) =>
        '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
    Future<void> edit(String key, String title, {int limit = 300}) async {
      final value = await askMusicText(
        context,
        title,
        initial: mark.text(key),
        maxLength: limit,
      );
      if (value != null) await personal.mark(track.id, {key: value});
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Detail lagu')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Artwork(url: song.artUrl, size: 170, radius: 24)),
          Text(song.title, style: Theme.of(context).textTheme.headlineSmall),
          Text('${song.artist} • ${song.album}'),
          FilledButton.icon(
            onPressed: () => player.state.previewId == track.id
                ? player.cancelPreview()
                : player.preview(track.id),
            icon: const Icon(Icons.headphones),
            label: Text(
              player.state.previewId == track.id
                  ? 'Hentikan pratinjau'
                  : 'Pratinjau 15 detik',
            ),
          ),
          if (song.missing || mark.text('problem').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(song.missing ? 'File hilang' : mark.text('problem')),
              subtitle: const Text(
                'Pilih kembali file asli yang sama untuk menjaga referensi playlist',
              ),
              trailing: const Icon(Icons.folder_open),
              onTap: () =>
                  context.read<CatalogCubit>().repairLocalTrack(track.id),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: 'Rating $star',
                  onPressed: () => personal.mark(track.id, {
                    'rating': mark.number('rating') == star ? 0 : star,
                  }),
                  icon: Icon(
                    mark.number('rating') >= star
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                  ),
                ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit metadata dan kredit'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _MetadataEditor(track: song),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Ganti cover'),
            onTap: () async {
              try {
                final uri = await context.read<PersonalAssets>().pickCover();
                if (uri != null) await personal.mark(track.id, {'cover': uri});
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cover gagal dibaca. Pilih JPG/PNG/WebP maksimal 8 MiB.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Catatan pribadi'),
            subtitle: Text(
              mark.text('notes').isEmpty
                  ? 'Chord, latihan atau kenangan'
                  : mark.text('notes'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => edit('notes', 'Catatan pribadi', limit: 10000),
          ),
          ListTile(
            leading: const Icon(Icons.mood),
            title: const Text('Mood'),
            subtitle: Text(mark.text('mood')),
            onTap: () => edit('mood', 'Mood', limit: 80),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Kelompok versi lagu'),
            subtitle: Text(
              mark.text('versionGroup').isEmpty
                  ? 'Nama yang sama untuk studio / live / akustik'
                  : mark.text('versionGroup'),
            ),
            onTap: () => edit('versionGroup', 'Kelompok versi', limit: 100),
          ),
          SwitchListTile(
            title: const Text('Kecualikan dari shuffle'),
            value: mark.flag('excludeShuffle'),
            onChanged: (value) =>
                personal.mark(track.id, {'excludeShuffle': value}),
          ),
          SwitchListTile(
            title: const Text('Sematkan lagu di Home'),
            value: mark.flag('pinned'),
            onChanged: (value) => personal.mark(track.id, {'pinned': value}),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: const Text('Tambah penanda waktu'),
            onTap: () async {
              final position = player.state.item?.id == track.id
                  ? player.state.position
                  : Duration.zero;
              final label = await askMusicText(
                context,
                'Penanda ${time(position.inMilliseconds)}',
                maxLength: 100,
              );
              if (label != null) {
                await personal.bookmark(track.id, position, label);
              }
            },
          ),
          for (final bookmark in mark.bookmarks)
            ListTile(
              leading: Text(time(bookmark['ms'] as int)),
              title: Text(bookmark['label'] as String),
              onTap: () async {
                if (player.state.item?.id != track.id) {
                  await player.playId(track.id);
                }
                await player.seek(
                  Duration(milliseconds: bookmark['ms'] as int),
                );
              },
              trailing: IconButton(
                tooltip: 'Hapus penanda',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    personal.removeBookmark(track.id, bookmark['ms'] as int),
              ),
            ),
          ListTile(
            title: const Text('Offset lirik (milidetik)'),
            subtitle: Text(
              '${mark.number('lyricOffset')} ms; positif memajukan lirik',
            ),
            onTap: () async {
              final value = await askMusicText(
                context,
                'Offset lirik',
                initial: '${mark.number('lyricOffset')}',
                maxLength: 8,
              );
              final offset = int.tryParse(value ?? '');
              if (offset != null) {
                await personal.mark(track.id, {
                  'lyricOffset': offset.clamp(-600000, 600000),
                });
              }
            },
          ),
          ExpansionTile(
            title: const Text('Informasi audio dan kredit'),
            children: [
              ListTile(
                title: Text(
                  'Format: ${Uri.tryParse(song.audioUrl)?.path.split('.').last.toUpperCase() ?? '—'}',
                ),
              ),
              FutureBuilder<int>(
                future: song.isLocal
                    ? File.fromUri(
                        Uri.parse(song.audioUrl),
                      ).length().catchError((_) => 0)
                    : Future.value(0),
                builder: (context, snapshot) => ListTile(
                  title: Text(
                    'Ukuran file: ${((snapshot.data ?? 0) / 1048576).toStringAsFixed(2)} MiB',
                  ),
                ),
              ),
              for (final key in [
                'bitrate',
                'sampleRate',
                'bitsPerSample',
                'composer',
                'writer',
                'year',
                'label',
                'disc',
                'track',
                'bpm',
                'key',
              ])
                if (song.info[key] != null && '${song.info[key]}'.isNotEmpty)
                  ListTile(
                    title: Text(key),
                    subtitle: Text('${song.info[key]}'),
                  ),
            ],
          ),
          ListTile(
            title: const Text('Statistik lagu'),
            subtitle: Text(
              '${mark.number('plays')} pemutaran • ${(mark.number('listenedMs') / 60000).toStringAsFixed(1)} menit didengarkan',
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataEditor extends StatefulWidget {
  const _MetadataEditor({required this.track});
  final Track track;
  @override
  State<_MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<_MetadataEditor> {
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final t = widget.track;
    final values = {
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'genre': t.genre,
      for (final key in [
        'composer',
        'writer',
        'year',
        'label',
        'disc',
        'track',
        'bpm',
        'key',
      ])
        key: '${t.info[key] ?? ''}',
    };
    for (final entry in values.entries) {
      _controllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit metadata'),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_controllers['title']!.text.trim().isEmpty) return;
                  setState(() => _busy = true);
                  await PersonalScope.maybeOf(
                    context,
                  )!.controller.mark(widget.track.id, {
                    for (final entry in _controllers.entries)
                      entry.key: entry.value.text.trim(),
                  });
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Simpan'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Perubahan disimpan di Swift Music. File audio asli tetap utuh.',
        ),
        const SizedBox(height: 16),
        for (final entry in _controllers.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: entry.value,
              maxLength: 300,
              decoration: InputDecoration(labelText: entry.key),
            ),
          ),
      ],
    ),
  );
}
