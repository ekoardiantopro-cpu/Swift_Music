import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/library/data/playlist_repository.dart';
import 'package:swift_music/features/library/domain/music_playlist.dart';
import 'package:swift_music/features/library/presentation/playlist_cubit.dart';
import 'package:swift_music/features/player/domain/lrc_document.dart';
import 'package:swift_music/features/catalog/data/audio_metadata_reader.dart';
import 'package:swift_music/features/catalog/data/local_audio_store.dart';
import 'package:swift_music/features/catalog/data/device_catalog_repository.dart';
import 'package:swift_music/features/catalog/data/music_folder_source.dart';
import 'package:swift_music/features/catalog/data/folder_registry.dart';

class _Tags implements AudioMetadataReader {
  @override
  Future<Map<String, dynamic>> read(File audio, File cover) async {
    await cover.writeAsBytes([1, 2, 3]);
    return {
      'title': 'Tagged song',
      'artist': 'Artist',
      'album': 'Album',
      'genre': 'Jazz',
      'durationMs': 12000,
    };
  }
}

class _Source implements RestorableMusicFolderSource {
  int reads = 0;
  bool extra = false;
  @override
  Future<MusicFolder?> pick() async => const MusicFolder('folder-uri', 'Music');
  @override
  Future<MusicFolder> restore(MusicFolder folder) async => folder;
  @override
  Future<void> forget(MusicFolder folder) async {}
  @override
  Future<void> release() async {}
  @override
  Future<List<FolderAudioFile>> list(
    MusicFolder folder,
    List<String> extensions,
  ) async => [
    const FolderAudioFile('one', 'one.mp3', size: 3, modifiedMs: 10),
    if (extra)
      const FolderAudioFile('two', 'two.flac', size: 3, modifiedMs: 20),
  ];
  @override
  Stream<List<int>> read(FolderAudioFile file) async* {
    reads++;
    yield file.uri == 'one' ? [1, 2, 3] : [4, 5, 6];
  }
}

void main() {
  test('LRC sorts stamps, fractions, translations and positive offset', () {
    final doc = LrcDocument.parse(
      '[offset:100]\n[00:03.2]Later\n[00:01.00][00:02.001]First\n[00:01]Translation',
    );
    expect(doc.lines.map((line) => line.time.inMilliseconds), [
      900,
      1901,
      3100,
    ]);
    expect(doc.lines.first.text, 'First\nTranslation');
    expect(doc.activeIndex(const Duration(milliseconds: 899)), -1);
    expect(doc.activeIndex(const Duration(milliseconds: 1901)), 1);
    expect(LrcDocument.parse('Plain lyrics').synced, isFalse);
  });

  test(
    'playlist edits deduplicate, reorder, remove and survive restart',
    () async {
      final repository = MemoryPlaylistRepository();
      final cubit = PlaylistCubit(repository);
      final id = (await cubit.create(' Morning '))!;
      await cubit.setTracks(id, ['a', 'b', 'a']);
      expect(cubit.state.playlists.single.trackIds, ['a', 'b']);
      await cubit.setTracks(id, ['b', 'a']);
      await cubit.rename(id, 'New name');
      await cubit.removeTrackEverywhere('b');
      await cubit.setSort(LibrarySort.artist);
      await cubit.close();
      final restored = PlaylistCubit(repository);
      await restored.rename(id, 'Restored');
      expect(restored.state.playlists.single.trackIds, ['a']);
      expect(restored.state.sort, LibrarySort.artist);
      await restored.delete(id);
      expect(restored.state.playlists, isEmpty);
      await restored.close();
    },
  );

  test('tag cover persists and removing app copy preserves source', () async {
    final root = await Directory.systemTemp.createTemp('swift-tags-');
    addTearDown(() => root.delete(recursive: true));
    final original = File('${root.path}/source.mp3');
    await original.writeAsBytes([1, 2, 3]);
    final store = LocalAudioStore(
      Directory('${root.path}/library'),
      metadata: _Tags(),
    );
    final track = await store.importAudio('source.mp3', original.openRead());
    expect(track.title, 'Tagged song');
    expect(track.artist, 'Artist');
    expect(track.duration, const Duration(seconds: 12));
    expect(await File.fromUri(Uri.parse(track.artUrl)).exists(), isTrue);
    expect((await store.loadTracks()).single.album, 'Album');
    await store.remove(track.id);
    expect(await store.loadTracks(), isEmpty);
    expect(await original.exists(), isTrue);
    expect(await store.directory.list().toList(), isEmpty);
  });

  test(
    'saved source restores, skips unchanged bytes and excludes deleted copies',
    () async {
      final root = await Directory.systemTemp.createTemp('swift-sources-');
      addTearDown(() => root.delete(recursive: true));
      final source = _Source();
      final store = LocalAudioStore(Directory('${root.path}/library'));
      final registry = FileFolderRegistry(File('${root.path}/sources.json'));
      final first = DeviceCatalogRepository(
        store,
        folders: source,
        registry: registry,
      );
      await first.initialize();
      final imported = await first.importFolder((_, _, _) {}, () => false);
      final id = first.savedFolders.single.id;
      final restored = DeviceCatalogRepository(
        store,
        folders: source,
        registry: registry,
      );
      await restored.initialize();
      await restored.rescanFolder(id, (_, _, _) {}, () => false);
      expect(source.reads, 1);
      source.extra = true;
      expect(
        await restored.rescanFolder(id, (_, _, _) {}, () => false),
        hasLength(1),
      );
      expect(source.reads, 2);
      await restored.removeTrack(imported.single.id);
      await restored.rescanFolder(id, (_, _, _) {}, () => false);
      expect(source.reads, 2);
      expect(restored.tracks.where((track) => track.isLocal), hasLength(1));
      await restored.forgetFolder(id);
      expect(await registry.load(), isEmpty);
      expect(await store.loadTracks(), hasLength(1));
    },
  );
}
