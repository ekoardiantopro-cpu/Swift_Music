import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../data/personal_repository.dart';
import '../domain/music_personalization.dart';

class PersonalCubit extends Cubit<PersonalState> {
  PersonalCubit(this.repository) : super(PersonalState());
  final PersonalRepository repository;
  Future<void> Function()? onCatalogChanged;
  Future<void> Function()? onSettingsChanged;
  Future<void> _writes = Future.value();
  Future<void> initialize() async {
    try {
      emit(await repository.load());
    } catch (_) {
      emit(PersonalState(error: 'Data pribadi belum dapat dibaca.'));
    }
  }

  Future<void> _commit({
    Map<String, dynamic>? settings,
    Map<String, SongMark>? songs,
    List<Map<String, dynamic>>? queues,
    List<String>? searches,
    List<Map<String, dynamic>>? savedSearches,
  }) async {
    if (isClosed) return;
    emit(
      PersonalState(
        settings: settings ?? state.settings,
        songs: songs ?? state.songs,
        queues: queues ?? state.queues,
        searches: searches ?? state.searches,
        savedSearches: savedSearches ?? state.savedSearches,
      ),
    );
    final snapshot = state;
    _writes = _writes.catchError((_) {}).then((_) => repository.save(snapshot));
    try {
      await _writes;
      if (settings != null) await onSettingsChanged?.call();
    } catch (_) {
      if (!isClosed) {
        emit(
          PersonalState(
            settings: state.settings,
            songs: state.songs,
            queues: state.queues,
            searches: state.searches,
            savedSearches: state.savedSearches,
            error: 'Perubahan data pribadi belum tersimpan.',
          ),
        );
      }
    }
  }

  Future<void> setting(String key, Object? value) =>
      _commit(settings: {...state.settings, key: value});
  Future<void> mark(String id, Map<String, dynamic> values) async {
    await _commit(songs: {...state.songs, id: state.song(id).update(values)});
    if (values.keys.any(
      [
        'title',
        'artist',
        'album',
        'genre',
        'cover',
        'lyrics',
        'composer',
        'writer',
        'year',
        'label',
        'disc',
        'track',
        'bpm',
        'key',
      ].contains,
    )) {
      await onCatalogChanged?.call();
    }
  }

  Track resolve(Track track) => state.song(track.id).apply(track);
  Future<void> bookmark(String id, Duration position, String label) {
    final items = [...state.song(id).bookmarks];
    items.removeWhere((item) => item['ms'] == position.inMilliseconds);
    items.add({
      'ms': position.inMilliseconds,
      'label': label.trim().isEmpty ? 'Penanda' : label.trim(),
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    items.sort((a, b) => (a['ms'] as int).compareTo(b['ms'] as int));
    return mark(id, {'bookmarks': items});
  }

  Future<void> removeBookmark(String id, int ms) => mark(id, {
    'bookmarks': state
        .song(id)
        .bookmarks
        .where((item) => item['ms'] != ms)
        .toList(),
  });
  Future<void> recordPlay(String id) async {
    if (state.flag('private')) return;
    await mark(id, {
      'plays': state.song(id).number('plays') + 1,
      'lastPlayed': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> listened(String id, int milliseconds) async {
    if (state.flag('private') || milliseconds <= 0) return;
    await mark(id, {
      'listenedMs': state.song(id).number('listenedMs') + milliseconds,
    });
  }

  Future<void> search(String query) async {
    final value = query.trim();
    if (value.isEmpty || state.flag('private')) return;
    await _commit(
      searches: [
        value,
        ...state.searches.where((q) => q != value),
      ].take(30).toList(),
    );
  }

  Future<void> saveSearch(
    String query, {
    Map<String, dynamic> filters = const {},
    String? name,
  }) => _commit(
    savedSearches: [
      {
        'query': query,
        'filters': filters,
        'name': name ?? (query.isEmpty ? 'Filter koleksi' : query),
        'at': DateTime.now().millisecondsSinceEpoch,
      },
      ...state.savedSearches.where(
        (item) =>
            item['query'] != query ||
            jsonEncode(item['filters'] ?? {}) != jsonEncode(filters),
      ),
    ].take(50).toList(),
  );
  Future<void> clearSearches() => _commit(searches: []);
  Future<void> saveQueue(
    String name,
    List<String> ids, {
    String? currentId,
    int positionMs = 0,
    bool history = false,
  }) async {
    if (history && state.flag('private')) return;
    if (ids.isEmpty) return;
    await _commit(
      queues: [
        {
          'name': name,
          'ids': ids,
          'currentId': currentId,
          'positionMs': positionMs,
          'history': history,
          'at': DateTime.now().millisecondsSinceEpoch,
        },
        ...state.queues,
      ].take(60).toList(),
    );
  }

  Future<void> deleteQueue(int at) =>
      _commit(queues: state.queues.where((item) => item['at'] != at).toList());
  List<Track> collection(String kind, List<Track> tracks, {String value = ''}) {
    final list = tracks
        .where(
          (t) => switch (kind) {
            'unheard' => state.song(t.id).number('plays') == 0,
            'rated' => state.song(t.id).number('rating') >= 4,
            'mood' =>
              state.song(t.id).text('mood').toLowerCase() ==
                  value.toLowerCase(),
            'artist' => t.artist == value,
            'album' => t.album == value,
            'version' => state.song(t.id).text('versionGroup') == value,
            'pinned' => state.song(t.id).flag('pinned'),
            _ => true,
          },
        )
        .toList();
    int compare(Track a, Track b) => switch (kind) {
      'mostPlayed' =>
        state
            .song(b.id)
            .number('plays')
            .compareTo(state.song(a.id).number('plays')),
      'rediscover' =>
        state
            .song(a.id)
            .number('lastPlayed')
            .compareTo(state.song(b.id).number('lastPlayed')),
      'newest' => ((b.info['importedAt'] as num?) ?? 0).compareTo(
        (a.info['importedAt'] as num?) ?? 0,
      ),
      'timeline' =>
        '${a.info['year'] ?? ''}|${a.album}|${a.info['disc'] ?? ''}|${a.info['track'] ?? ''}'
            .compareTo(
              '${b.info['year'] ?? ''}|${b.album}|${b.info['disc'] ?? ''}|${b.info['track'] ?? ''}',
            ),
      _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
    list.sort(compare);
    return list;
  }

  @override
  Future<void> close() async {
    await _writes.catchError((_) {});
    return super.close();
  }
}

class PersonalScope extends InheritedWidget {
  const PersonalScope({
    super.key,
    required this.controller,
    required this.state,
    required super.child,
  });
  final PersonalCubit controller;
  final PersonalState state;
  static PersonalScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PersonalScope>();
  @override
  bool updateShouldNotify(PersonalScope oldWidget) => oldWidget.state != state;
}
