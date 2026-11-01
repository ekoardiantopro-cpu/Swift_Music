import 'package:flutter/material.dart';
import '../../catalog/domain/music_filter.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/domain/saved_music_folder.dart';

class SearchFilters extends StatefulWidget {
  const SearchFilters({
    super.key,
    required this.filter,
    required this.tracks,
    required this.folders,
    required this.onChanged,
  });
  final MusicFilter filter;
  final List<Track> tracks;
  final List<SavedMusicFolder> folders;
  final ValueChanged<MusicFilter> onChanged;
  @override
  State<SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<SearchFilters> {
  bool _expanded = false;
  late final _artist = TextEditingController(text: widget.filter.artist ?? '');
  late final _album = TextEditingController(text: widget.filter.album ?? '');
  @override
  void didUpdateWidget(SearchFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_artist.text != (widget.filter.artist ?? '')) {
      _artist.text = widget.filter.artist ?? '';
    }
    if (_album.text != (widget.filter.album ?? '')) {
      _album.text = widget.filter.album ?? '';
    }
  }

  @override
  void dispose() {
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final folders = widget.folders;
    final onChanged = widget.onChanged;
    final extensions =
        (_expanded ? widget.tracks : <Track>[])
            .where((track) => track.isLocal)
            .map(
              (track) =>
                  Uri.parse(track.audioUrl).path.split('.').last.toLowerCase(),
            )
            .toSet()
            .toList()
          ..sort();
    Widget field(
      String label,
      String? value,
      Map<String, String> options,
      ValueChanged<String?> change,
    ) {
      final values = {
        ...options,
        if (value != null && !options.containsKey(value)) value: value,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label:$value'),
          initialValue: value ?? '',
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Semua')),
            for (final entry in values.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => change(value == '' ? null : value),
        ),
      );
    }

    void update({
      String? folder,
      String? extension,
      String? artist,
      String? album,
      String? duration,
    }) => onChanged(
      MusicFilter(
        folder: folder,
        extension: extension,
        artist: artist,
        album: album,
        duration: duration,
      ),
    );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(filter.active ? 'Filter koleksi aktif' : 'Filter koleksi'),
      leading: const Icon(Icons.tune),
      onExpansionChanged: (value) => setState(() => _expanded = value),
      children: !_expanded
          ? []
          : [
              field(
                'Folder',
                filter.folder,
                {for (final folder in folders) folder.id: folder.name},
                (value) => update(
                  folder: value,
                  extension: filter.extension,
                  artist: filter.artist,
                  album: filter.album,
                  duration: filter.duration,
                ),
              ),
              field(
                'Format',
                filter.extension,
                {for (final ext in extensions) ext: ext.toUpperCase()},
                (value) => update(
                  folder: filter.folder,
                  extension: value,
                  artist: filter.artist,
                  album: filter.album,
                  duration: filter.duration,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _artist,
                  decoration: const InputDecoration(labelText: 'Artis'),
                  onChanged: (value) => update(
                    folder: filter.folder,
                    extension: filter.extension,
                    artist: value.isEmpty ? null : value,
                    album: filter.album,
                    duration: filter.duration,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _album,
                  decoration: const InputDecoration(labelText: 'Album'),
                  onChanged: (value) => update(
                    folder: filter.folder,
                    extension: filter.extension,
                    artist: filter.artist,
                    album: value.isEmpty ? null : value,
                    duration: filter.duration,
                  ),
                ),
              ),
              field(
                'Durasi',
                filter.duration,
                const {
                  'short': 'Maksimal 3 menit',
                  'long': 'Lebih dari 3 menit',
                  'unknown': 'Durasi belum diketahui',
                },
                (value) => update(
                  folder: filter.folder,
                  extension: filter.extension,
                  artist: filter.artist,
                  album: filter.album,
                  duration: value,
                ),
              ),
              if (filter.active)
                TextButton(
                  onPressed: () => onChanged(const MusicFilter()),
                  child: const Text('Reset filter'),
                ),
            ],
    );
  }
}
