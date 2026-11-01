import 'dart:convert';
import '../domain/music_playlist.dart';

class CollectionBackup {
  CollectionBackup({required this.playlists, required this.likes});
  final List<MusicPlaylist> playlists;
  final Set<String> likes;
  static const maxBytes = 2 * 1024 * 1024;
  List<int> encode() {
    final bytes = utf8.encode(
      jsonEncode({
        'app': 'Swift Music',
        'version': 1,
        'playlists': playlists
            .map((playlist) => playlist.copyWith(cover: '').toJson())
            .toList(),
        'likes': likes.toList(),
      }),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Cadangan melebihi 2 MiB.');
    }
    decode(bytes); // Never export a backup that this version cannot restore.
    return bytes;
  }

  static CollectionBackup decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Cadangan terlalu besar.');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (json['app'] != 'Swift Music' ||
        json['version'] != 1 ||
        json['playlists'] is! List ||
        json['likes'] is! List) {
      throw const FormatException('Bukan cadangan Swift Music yang didukung.');
    }
    final lists = json['playlists'] as List;
    if (lists.length > 500 || (json['likes'] as List).length > 50000) {
      throw const FormatException('Cadangan terlalu besar.');
    }
    final playlists = lists
        .map(
          (value) => MusicPlaylist.fromJson({
            ...Map<String, dynamic>.from(value as Map),
            'cover': '',
          }),
        )
        .toList();
    final ids = <String>{...(json['likes'] as List).cast<String>()};
    var count = ids.length;
    for (final playlist in playlists) {
      if (playlist.description.length > 2000 || playlist.folder.length > 80) {
        throw const FormatException('Deskripsi/folder playlist tidak valid.');
      }
      if (playlist.trackLabels.length > 50000 ||
          playlist.trackLabels.values.any((label) => label.length > 500)) {
        throw const FormatException('Label lagu tidak valid.');
      }
      if (playlist.name.trim().isEmpty || playlist.name.length > 80) {
        throw const FormatException('Nama playlist tidak valid.');
      }
      ids.addAll(playlist.trackIds);
      count += playlist.trackIds.length;
    }
    if (count > 50000 ||
        ids.any(
          (id) => !RegExp(r'^(local-[a-f0-9]{64}|demo-\d+)$').hasMatch(id),
        )) {
      throw const FormatException('Referensi lagu tidak valid.');
    }
    return CollectionBackup(
      playlists: playlists,
      likes: (json['likes'] as List).cast<String>().toSet(),
    );
  }
}
