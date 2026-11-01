import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../data/collection_backup.dart';
import 'library_cubit.dart';
import 'playlist_cubit.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Proses gagal. Gunakan cadangan Swift Music JSON maksimal 2 MiB atau coba lokasi penyimpanan lain.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final backup = CollectionBackup(
      playlists: context
          .read<PlaylistCubit>()
          .state
          .playlists
          .map(
            (playlist) => playlist.copyWith(
              trackLabels: {
                ...playlist.trackLabels,
                for (final track in context.read<CatalogCubit>().state.tracks)
                  if (playlist.trackIds.contains(track.id))
                    track.id: '${track.title} — ${track.artist}',
              },
            ),
          )
          .toList(),
      likes: context.read<LibraryCubit>().state.likes,
    );
    final uri = await FilePicker.saveFile(
      fileName: 'swift-music-backup.json',
      bytes: Uint8List.fromList(backup.encode()),
      mimeType: 'application/json',
      dialogTitle: 'Simpan cadangan Swift Music',
    );
    if (mounted && uri != null) {
      setState(() => _message = 'Cadangan berhasil disimpan.');
    }
  });
  Future<void> _import() => _run(() async {
    final playlists = context.read<PlaylistCubit>();
    final library = context.read<LibraryCubit>();
    final catalog = context.read<CatalogCubit>();
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Pilih cadangan Swift Music',
    );
    if (file == null) return;
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > CollectionBackup.maxBytes) {
        throw const FormatException('Cadangan terlalu besar.');
      }
      bytes.addAll(chunk);
    }
    final backup = CollectionBackup.decode(bytes);
    final available = catalog.state.tracks.map((track) => track.id).toSet();
    final referenced = {
      ...backup.likes,
      for (final playlist in backup.playlists) ...playlist.trackIds,
    };
    final missing = referenced.difference(available).length;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulihkan koleksi?'),
        content: Text(
          '${backup.playlists.length} playlist, ${backup.likes.length} favorit. $missing lagu belum tersedia di perangkat ini.\n\nKoleksi digabung tanpa menghapus playlist yang ada. File musik tidak disertakan; impor file asli yang sama untuk mencocokkan lagu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final added = await playlists.mergeBackup(backup.playlists);
    await library.mergeLikes(backup.likes);
    if (mounted) {
      setState(
        () => _message =
            '$added playlist ditambahkan. $missing lagu perlu diimpor kembali.',
      );
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cadangan koleksi')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Cadangkan playlist dan favorit ke file JSON. File musik, izin folder, dan lirik tidak disertakan. File musik yang sama akan dicocokkan berdasarkan isi saat diimpor pada perangkat baru.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.upload_file),
          label: const Text('Simpan cadangan'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.restore),
          label: const Text('Pulihkan cadangan'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(_message!),
          ),
      ],
    ),
  );
}
