import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/music_playlist.dart';

abstract interface class PlaylistRepository {
  Future<(List<MusicPlaylist>, LibrarySort)> load();
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort);
}

class LocalPlaylistRepository implements PlaylistRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<(List<MusicPlaylist>, LibrarySort)> load() async {
    final raw = await _preferences.getString('music_collections');
    if (raw == null) return (<MusicPlaylist>[], LibrarySort.newest);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final result = <MusicPlaylist>[];
    for (final record in json['playlists'] as List? ?? []) {
      try {
        result.add(
          MusicPlaylist.fromJson(Map<String, dynamic>.from(record as Map)),
        );
      } catch (_) {}
    }
    final sort =
        LibrarySort.values
            .where((value) => value.name == json['sort'])
            .firstOrNull ??
        LibrarySort.newest;
    return (result, sort);
  }

  @override
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort) =>
      _preferences.setString(
        'music_collections',
        jsonEncode({
          'playlists': playlists.map((list) => list.toJson()).toList(),
          'sort': sort.name,
        }),
      );
}

class MemoryPlaylistRepository implements PlaylistRepository {
  List<MusicPlaylist> playlists = [];
  LibrarySort sort = LibrarySort.newest;
  @override
  Future<(List<MusicPlaylist>, LibrarySort)> load() async => (playlists, sort);
  @override
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort) async {
    this.playlists = [...playlists];
    this.sort = sort;
  }
}
