import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../data/playlist_repository.dart';
import '../domain/music_playlist.dart';

class PlaylistState {
  PlaylistState({
    List<MusicPlaylist> playlists = const [],
    this.sort = LibrarySort.newest,
    this.error,
  }) : playlists = List.unmodifiable(playlists);
  final List<MusicPlaylist> playlists;
  final LibrarySort sort;
  final String? error;
}

class PlaylistCubit extends Cubit<PlaylistState> {
  PlaylistCubit(this._repository) : super(PlaylistState()) {
    _ready = _initialize();
  }
  final PlaylistRepository _repository;
  late final Future<void> _ready;
  Future<void> _writes = Future.value();
  int _revision = 0;
  int _nextId = 0;
  final List<List<MusicPlaylist>> _undo = [];
  bool get canUndo => _undo.isNotEmpty;
  void _remember() {
    _undo.add(state.playlists);
    if (_undo.length > 20) _undo.removeAt(0);
  }

  List<Map<String, dynamic>> _log(MusicPlaylist playlist, String action) => [
    {'at': DateTime.now().millisecondsSinceEpoch, 'action': action},
    ...playlist.changes,
  ].take(100).toList();
  Future<void> undo() async {
    await _ready;
    if (isClosed || _undo.isEmpty) return;
    emit(PlaylistState(playlists: _undo.removeLast(), sort: state.sort));
    await _persist();
  }

  Future<void> details(
    String id, {
    String? description,
    String? folder,
    String? cover,
  }) async {
    await _ready;
    if (isClosed ||
        (description?.length ?? 0) > 2000 ||
        (folder?.length ?? 0) > 80) {
      return;
    }
    _remember();
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (p) => p.id == id
                  ? p.copyWith(
                      description: description,
                      folder: folder,
                      cover: cover,
                      changes: _log(p, 'Detail playlist diubah'),
                    )
                  : p,
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<String?> mergePlaylists(List<String> ids, String name) async {
    await _ready;
    if (isClosed || name.trim().isEmpty || name.length > 80) return null;
    final chosen = ids
        .map((id) => state.playlists.where((p) => p.id == id).firstOrNull)
        .whereType<MusicPlaylist>()
        .toList();
    if (chosen.length < 2) return null;
    _remember();
    final id = 'playlist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    emit(
      PlaylistState(
        playlists: [
          ...state.playlists,
          MusicPlaylist(
            id: id,
            name: name.trim(),
            trackIds: [for (final p in chosen) ...p.trackIds],
            trackLabels: {for (final p in chosen) ...p.trackLabels},
            description: 'Gabungan ${chosen.length} playlist',
          ),
        ],
        sort: state.sort,
      ),
    );
    await _persist();
    return id;
  }

  Future<void> _initialize() async {
    try {
      final (playlists, sort) = await _repository.load();
      if (!isClosed) emit(PlaylistState(playlists: playlists, sort: sort));
    } catch (_) {
      if (!isClosed) {
        emit(PlaylistState(error: 'Playlist tersimpan belum dapat dibaca.'));
      }
    }
  }

  Future<void> _persist() async {
    final revision = ++_revision;
    final lists = state.playlists;
    final sort = state.sort;
    _writes = _writes
        .catchError((_) {})
        .then((_) => _repository.save(lists, sort));
    try {
      await _writes;
    } catch (_) {
      if (!isClosed && revision == _revision) {
        emit(
          PlaylistState(
            playlists: state.playlists,
            sort: state.sort,
            error: 'Perubahan playlist belum tersimpan. Coba lagi.',
          ),
        );
      }
    }
  }

  Future<String?> create(String name) async {
    await _ready;
    name = name.trim();
    if (isClosed || name.isEmpty || name.length > 80) return null;
    final id = 'playlist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    _remember();
    emit(
      PlaylistState(
        playlists: [
          ...state.playlists,
          MusicPlaylist(id: id, name: name),
        ],
        sort: state.sort,
      ),
    );
    await _persist();
    return id;
  }

  Future<void> rename(String id, String name) async {
    await _ready;
    if (name.trim().isEmpty || name.trim().length > 80 || isClosed) return;
    _remember();
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (list) => list.id == id
                  ? list.copyWith(
                      name: name.trim(),
                      changes: _log(list, 'Nama playlist diubah'),
                    )
                  : list,
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> delete(String id) async {
    await _ready;
    if (isClosed) return;
    _remember();
    emit(
      PlaylistState(
        playlists: state.playlists.where((list) => list.id != id).toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<int> mergeBackup(List<MusicPlaylist> incoming) async {
    await _ready;
    if (isClosed) return 0;
    final lists = [...state.playlists];
    _remember();
    var added = 0;
    for (final playlist in incoming) {
      if (lists.any(
        (existing) =>
            existing.name == playlist.name &&
            existing.trackIds.join('|') == playlist.trackIds.join('|'),
      )) {
        continue;
      }
      lists.add(
        MusicPlaylist(
          id: 'playlist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
          name: playlist.name,
          trackIds: playlist.trackIds,
          trackLabels: playlist.trackLabels,
          description: playlist.description,
          folder: playlist.folder,
          changes: playlist.changes,
        ),
      );
      added++;
    }
    emit(PlaylistState(playlists: lists, sort: state.sort));
    await _persist();
    return added;
  }

  Future<void> setTracks(String id, List<String> ids) async {
    await _ready;
    if (isClosed) return;
    _remember();
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (list) => list.id == id
                  ? list.copyWith(
                      trackIds: ids,
                      changes: _log(
                        list,
                        'Susunan lagu diubah (${ids.toSet().length} lagu)',
                      ),
                    )
                  : list,
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> addTrack(String id, String trackId) async {
    await _ready;
    final list = state.playlists.where((list) => list.id == id).firstOrNull;
    if (list != null) await setTracks(id, [...list.trackIds, trackId]);
  }

  Future<void> removeTrackEverywhere(String id) async {
    await _ready;
    if (isClosed) return;
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (list) => list.copyWith(
                trackIds: list.trackIds
                    .where((trackId) => trackId != id)
                    .toList(),
              ),
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> setSort(LibrarySort sort) async {
    await _ready;
    if (!isClosed) {
      emit(PlaylistState(playlists: state.playlists, sort: sort));
      await _persist();
    }
  }

  List<Track> sorted(Iterable<Track> tracks) {
    final result = tracks.toList();
    if (state.sort == LibrarySort.newest) return result.reversed.toList();
    String key(Track track) => switch (state.sort) {
      LibrarySort.artist => track.artist,
      LibrarySort.album => track.album,
      _ => track.title,
    };
    result.sort((a, b) => key(a).toLowerCase().compareTo(key(b).toLowerCase()));
    return result;
  }

  @override
  Future<void> close() async {
    await _writes.catchError((_) {});
    return super.close();
  }
}
