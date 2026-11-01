import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/catalog/data/device_catalog_repository.dart';
import 'package:swift_music/features/catalog/data/local_audio_store.dart';
import 'package:swift_music/features/catalog/data/music_folder_source.dart';

class _Folders implements MusicFolderSource {
  bool released = false;
  bool cancelPicker = false;
  final files = [
    const FolderAudioFile('a', 'Song.MP3'),
    const FolderAudioFile('b', 'Copy.mp3'),
    const FolderAudioFile('c', 'Nested.flac'),
    const FolderAudioFile('bad', 'Broken.wav'),
  ];
  @override
  Future<MusicFolder?> pick() async =>
      cancelPicker ? null : const MusicFolder('folder', 'Music');
  @override
  Future<List<FolderAudioFile>> list(
    MusicFolder folder,
    List<String> extensions,
  ) async => [...files];
  @override
  Stream<List<int>> read(FolderAudioFile file) async* {
    if (file.uri == 'bad') throw const FileSystemException('unreadable');
    yield file.uri == 'c' ? [4, 5, 6] : [1, 2, 3];
  }

  @override
  Future<void> release() async {
    released = true;
  }
}

class _InterruptedFolder extends _Folders {
  bool cancelled = false;
  @override
  Stream<List<int>> read(FolderAudioFile file) async* {
    yield [1, 2, 3];
    cancelled = true;
    yield [4, 5, 6];
  }
}

void main() {
  test(
    'cancelling a file mid-stream removes partial copies and releases access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'swift-mid-cancel',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = _InterruptedFolder();
      final repository = DeviceCatalogRepository(
        LocalAudioStore(directory),
        folders: source,
      );
      await repository.importFolder((_, _, _) {}, () => source.cancelled);
      expect(await directory.list().toList(), isEmpty);
      expect(source.released, isTrue);
      expect(repository.lastImportSummary, contains('dihentikan'));
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'folder imports deduplicate, preserve partial success and release access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'swift-folder-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = _Folders();
      final repository = DeviceCatalogRepository(
        LocalAudioStore(directory),
        folders: source,
      );
      try {
        await repository.importFolder((_, _, _) {}, () => false);
      } catch (_) {}
      expect(repository.tracks.where((track) => track.isLocal), hasLength(2));
      expect(repository.lastImportSummary, contains('1 duplikat'));
      expect(repository.lastImportSummary, contains('1 file gagal'));
      expect(source.released, isTrue);
      final restored = await LocalAudioStore(directory).loadTracks();
      expect(restored, hasLength(2));
      expect(
        repository.savedFolders.single.fingerprints.values.where(
          (value) => value.startsWith('unknown|'),
        ),
        hasLength(3),
      );
    },
  );
  test(
    'folder cancellation leaves no partial audio and picker cancel is silent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'swift-folder-cancel',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = _Folders();
      final repository = DeviceCatalogRepository(
        LocalAudioStore(directory),
        folders: source,
      );
      await repository.importFolder((_, _, _) {}, () => true);
      expect(repository.tracks.where((track) => track.isLocal), isEmpty);
      expect(source.released, isTrue);
      source.cancelPicker = true;
      expect(await repository.importFolder((_, _, _) {}, () => false), isEmpty);
      expect(repository.lastImportSummary, isNull);
    },
  );
  test(
    'document URI reads are chunked and native handles close on stream errors',
    () async {
      const channel = MethodChannel('test/swift-folder');
      final calls = <String>[];
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'pickFolder':
                return {'uri': 'content://folder', 'name': 'Music'};
              case 'listFolder':
                return [
                  {'uri': 'content://song', 'name': 'song.m4a'},
                ];
              case 'openFile':
                return 1;
              case 'readChunk':
                if (reads++ == 0) return Uint8List.fromList([1, 2, 3]);
                throw PlatformException(code: 'read_error');
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final source = NativeMusicFolderSource(channel: channel, useNative: true);
      final folder = await source.pick();
      final files = await source.list(folder!, LocalAudioStore.extensions);
      await expectLater(
        source.read(files.single).drain<void>(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.last, 'closeFile');
      await source.release();
      expect(calls.last, 'releaseFolder');
    },
  );
}
