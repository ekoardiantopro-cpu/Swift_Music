import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/catalog/domain/track.dart';
import 'package:swift_music/features/catalog/domain/fuzzy_search.dart';
import 'package:swift_music/features/personal/data/personal_repository.dart';
import 'package:swift_music/features/personal/domain/music_personalization.dart';
import 'package:swift_music/features/personal/presentation/personal_cubit.dart';
import 'package:swift_music/features/library/data/playlist_repository.dart';
import 'package:swift_music/features/library/data/collection_backup.dart';
import 'package:swift_music/features/library/presentation/playlist_cubit.dart';
import 'package:swift_music/features/player/domain/queue_summary.dart';

const _track = Track(
  id: 'demo-1',
  title: 'Original',
  artist: 'Artist',
  album: 'Album',
  genre: 'Jazz',
  audioUrl: 'file:///original.mp3',
  artUrl: '',
  lyrics: 'Old',
);
void main() {
  test(
    'personal metadata overlays never modify identity or original audio',
    () async {
      final repo = MemoryPersonalRepository();
      final cubit = PersonalCubit(repo);
      await cubit.initialize();
      var refreshes = 0;
      cubit.onCatalogChanged = () async {
        refreshes++;
      };
      await cubit.mark('demo-1', {
        'title': 'New',
        'artist': 'New Artist',
        'rating': 5,
        'lyrics': '[00:01]Hello',
        'year': '2024',
      });
      final track = cubit.resolve(_track);
      expect(track.title, 'New');
      expect(track.id, _track.id);
      expect(track.audioUrl, _track.audioUrl);
      expect(_track.title, 'Original');
      expect(track.lyrics, '[00:01]Hello');
      expect(track.info['year'], '2024');
      expect(refreshes, 1);
      await cubit.recordPlay('demo-1');
      expect(refreshes, 1);
      await cubit.close();
      final restored = PersonalCubit(repo);
      await restored.initialize();
      expect(restored.state.song('demo-1').number('rating'), 5);
      await restored.close();
    },
  );
  test(
    'privacy disables history/statistics and bookmarks deduplicate by time',
    () async {
      final cubit = PersonalCubit(MemoryPersonalRepository());
      await cubit.initialize();
      await cubit.setting('private', true);
      await cubit.recordPlay('demo-1');
      await cubit.listened('demo-1', 5000);
      await cubit.search('hidden');
      expect(cubit.state.song('demo-1').number('plays'), 0);
      expect(cubit.state.searches, isEmpty);
      await cubit.setting('private', false);
      await cubit.recordPlay('demo-1');
      await cubit.listened('demo-1', 5000);
      await cubit.bookmark('demo-1', const Duration(seconds: 20), 'First');
      await cubit.bookmark('demo-1', const Duration(seconds: 10), 'Earlier');
      await cubit.bookmark('demo-1', const Duration(seconds: 20), 'Updated');
      expect(cubit.state.song('demo-1').bookmarks.map((b) => b['ms']), [
        10000,
        20000,
      ]);
      expect(cubit.state.song('demo-1').bookmarks.last['label'], 'Updated');
      expect(cubit.state.song('demo-1').number('listenedMs'), 5000);
      await cubit.close();
    },
  );
  test('saved query/filter and queues survive JSON round trip', () async {
    final cubit = PersonalCubit(MemoryPersonalRepository());
    await cubit.initialize();
    await cubit.saveSearch(
      'Original',
      filters: {'extension': 'mp3'},
      name: 'MP3',
    );
    await cubit.saveSearch(
      'Original',
      filters: {'extension': 'flac'},
      name: 'FLAC',
    );
    await cubit.saveQueue(
      'Work',
      ['demo-1'],
      currentId: 'demo-1',
      positionMs: 35000,
    );
    final restored = PersonalState.fromJson(
      jsonDecode(jsonEncode(cubit.state.toJson())) as Map<String, dynamic>,
    );
    expect(restored.savedSearches, hasLength(2));
    expect(
      (restored.savedSearches.first['filters'] as Map)['extension'],
      'flac',
    );
    expect(restored.queues.single['positionMs'], 35000);
    await cubit.close();
  });
  test('smart collections use actual play and rating data', () async {
    final cubit = PersonalCubit(MemoryPersonalRepository());
    await cubit.initialize();
    final second = _track.copyWith(title: 'Second');
    await cubit.mark('demo-1', {'rating': 5, 'plays': 3, 'mood': 'Focus'});
    expect(cubit.collection('rated', [_track]), hasLength(1));
    expect(cubit.collection('unheard', [_track]), isEmpty);
    expect(cubit.collection('mood', [_track], value: 'focus'), hasLength(1));
    expect(cubit.collection('mostPlayed', [second]).single.id, 'demo-1');
    await cubit.close();
  });
  test(
    'playlist merge/undo retains sources and backup omits private cover paths',
    () async {
      final cubit = PlaylistCubit(MemoryPlaylistRepository());
      final a = (await cubit.create('A'))!;
      final b = (await cubit.create('B'))!;
      await cubit.setTracks(a, ['demo-1', 'demo-2']);
      await cubit.setTracks(b, ['demo-2', 'demo-3']);
      await cubit.details(
        a,
        description: 'Description',
        folder: 'Work',
        cover: 'file:///private/cover.png',
      );
      final merged = await cubit.mergePlaylists([a, b], 'Together');
      expect(cubit.state.playlists.last.trackIds, [
        'demo-1',
        'demo-2',
        'demo-3',
      ]);
      await cubit.undo();
      expect(cubit.state.playlists.any((p) => p.id == merged), isFalse);
      expect(cubit.state.playlists.first.description, 'Description');
      final backup = CollectionBackup(
        playlists: cubit.state.playlists,
        likes: {},
      );
      final bytes = backup.encode();
      expect(utf8.decode(bytes), isNot(contains('/private/')));
      expect(CollectionBackup.decode(bytes).playlists.first.folder, 'Work');
      await cubit.close();
    },
  );
  test('fuzzy search tolerates typo and ranks exact results first', () {
    expect(FuzzyMusicSearch.score('swfit', 'Swift Music'), isNotNull);
    expect(FuzzyMusicSearch.score('musci', 'Swift Music'), isNotNull);
    expect(FuzzyMusicSearch.score('zzzzzzz', 'Swift Music'), isNull);
    expect(FuzzyMusicSearch.score('s', 'Swift Music'), 0);
    final first = _track.copyWith(title: 'Original');
    final second = _track.copyWith(title: 'Orignal');
    expect(
      FuzzyMusicSearch.search([second, first], 'Original').first.title,
      'Original',
    );
  });
  test('queue duration/ETA respects current position and playback speed', () {
    final summary = QueueSummary(
      durations: [const Duration(minutes: 3), const Duration(minutes: 4)],
      currentIndex: 0,
      position: const Duration(minutes: 1),
      speed: 2,
      shuffled: false,
      now: DateTime.utc(2026, 10, 30, 10),
    );
    expect(summary.total, const Duration(minutes: 7));
    expect(summary.eta, DateTime.utc(2026, 10, 30, 10, 3));
    expect(
      QueueSummary(
        durations: [null],
        currentIndex: 0,
        position: Duration.zero,
        speed: 1,
        shuffled: false,
        now: DateTime.now(),
      ).eta,
      isNull,
    );
  });
}
