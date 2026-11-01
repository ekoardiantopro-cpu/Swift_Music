import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:swift_music/features/catalog/data/local_audio_store.dart';

void main() {
  late Directory temporary;
  late LocalAudioStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'swift-music-local-test-',
    );
    store = LocalAudioStore(Directory(p.join(temporary.path, 'library')));
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'import copies bytes and restores a playable file URI after restart',
    () async {
      final original = File(p.join(temporary.path, 'My song.MP3'));
      await original.writeAsBytes([1, 2, 3, 4]);
      final imported = await store.importAudio(
        p.basename(original.path),
        original.openRead(),
      );
      await original.delete();
      final restored = await LocalAudioStore(store.directory).loadTracks();
      expect(restored.single.id, imported.id);
      expect(restored.single.title, 'My song');
      expect(restored.single.isLocal, isTrue);
      expect(
        await File.fromUri(Uri.parse(restored.single.audioUrl)).readAsBytes(),
        [1, 2, 3, 4],
      );
    },
  );

  test('identical audio with different filenames is stored once', () async {
    final first = await store.importAudio('First.mp3', Stream.value([1, 2, 3]));
    final second = await store.importAudio(
      'Other name.wav',
      Stream.value([1, 2, 3]),
    );
    expect(second.id, first.id);
    expect(await store.loadTracks(), hasLength(1));
    expect(
      await store.directory
          .list()
          .where((f) => f.path.endsWith('.part'))
          .length,
      0,
    );
  });

  test('relative metadata survives an application directory move', () async {
    await store.importAudio('Portable.m4a', Stream.value([1, 2, 3]));
    final moved = await store.directory.rename(
      p.join(temporary.path, 'new-sandbox'),
    );
    final restored = await LocalAudioStore(moved).loadTracks();
    expect(
      File.fromUri(Uri.parse(restored.single.audioUrl)).parent.path,
      moved.path,
    );
  });

  test(
    'corrupt metadata and missing audio do not prevent loading other tracks',
    () async {
      final good = await store.importAudio(
        'Good.flac',
        Stream.value([1, 2, 3]),
      );
      final missing = await store.importAudio(
        'Missing.wav',
        Stream.value([4, 5, 6]),
      );
      await File.fromUri(Uri.parse(missing.audioUrl)).delete();
      await File(
        p.join(store.directory.path, 'broken.json'),
      ).writeAsString('{bad json');
      await File(
        p.join(store.directory.path, 'incomplete.json'),
      ).writeAsString('{"file":"invalid.mp3"}');
      final restored = await store.loadTracks();
      expect(restored.where((track) => !track.missing).single.id, good.id);
      expect(restored.where((track) => track.missing).single.id, missing.id);
    },
  );

  test(
    'empty, unsupported and interrupted imports are rejected without temp files',
    () async {
      await expectLater(
        store.importAudio('Empty.mp3', const Stream.empty()),
        throwsFormatException,
      );
      await expectLater(
        store.importAudio('Document.txt', Stream.value([1])),
        throwsFormatException,
      );
      await expectLater(
        store.importAudio(
          'Broken.mp3',
          Stream.error(const FileSystemException('read failed')),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.loadTracks(), isEmpty);
      expect(await store.directory.list().length, 0);
    },
  );
}
