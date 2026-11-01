import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/catalog/domain/catalog_repository.dart';
import 'package:swift_music/features/catalog/domain/track.dart';
import 'package:swift_music/features/catalog/presentation/catalog_cubit.dart';

const _local = Track(
  id: 'local-1',
  title: 'My audio',
  artist: 'Lagu lokal',
  album: 'On this device',
  genre: 'Local',
  audioUrl: 'file:///music/one.mp3',
  artUrl: '',
  lyrics: '',
);

class _Catalog implements CatalogRepository {
  @override
  final List<Track> tracks = [];
  @override
  List<Track> search(String query, {String? genre}) => tracks;
}

void main() {
  test(
    'folder progress and cancellation queue already completed imports',
    () async {
      final repository = _Catalog();
      final gate = Completer<void>();
      late bool Function() cancelled;
      final queued = <Track>[];
      final cubit = CatalogCubit(
        repository,
        importFolder: (progress, isCancelled) async {
          cancelled = isCancelled;
          progress(0, 0, 'Music');
          await gate.future;
          repository.tracks.add(_local);
          progress(1, 2, 'Music');
          return [_local];
        },
        onAdded: (tracks) async {
          queued.addAll(tracks);
        },
      );
      final operation = cubit.importFromFolder();
      expect(cubit.state.importing, isTrue);
      expect(cubit.state.folder, 'Music');
      cubit.cancelImport();
      expect(cancelled(), isTrue);
      gate.complete();
      await operation;
      expect(queued.single.id, _local.id);
      expect(cubit.state.importing, isFalse);
      await cubit.close();
    },
  );
  test(
    'import updates catalog and audio queue once; overlapping picker is ignored',
    () async {
      final repository = _Catalog();
      final picked = Completer<List<Track>>();
      var pickerCalls = 0;
      final queue = <Track>[];
      final cubit = CatalogCubit(
        repository,
        importAudio: () {
          pickerCalls++;
          return picked.future;
        },
        onAdded: (tracks) async {
          queue.addAll(tracks);
        },
      );
      final firstImport = cubit.importFromDevice();
      await cubit.importFromDevice();
      expect(pickerCalls, 1);
      expect(cubit.state.importing, isTrue);
      repository.tracks.add(_local);
      picked.complete([_local]);
      await firstImport;
      expect(cubit.state.tracks.single.isLocal, isTrue);
      expect(queue.single.id, _local.id);
      expect(cubit.state.importing, isFalse);
      await cubit.close();
    },
  );

  test('cancel does not touch playback queue or show an error', () async {
    var updatedQueue = false;
    final cubit = CatalogCubit(
      _Catalog(),
      importAudio: () async => [],
      onAdded: (_) async {
        updatedQueue = true;
      },
    );
    await cubit.importFromDevice();
    expect(updatedQueue, isFalse);
    expect(cubit.state.message, isNull);
    expect(cubit.state.importing, isFalse);
    await cubit.close();
  });

  test('partial failure still queues successfully imported files', () async {
    final repository = _Catalog();
    final queue = <Track>[];
    final cubit = CatalogCubit(
      repository,
      importAudio: () async {
        repository.tracks.add(_local);
        throw AudioImportException([_local], 1);
      },
      onAdded: (tracks) async {
        queue.addAll(tracks);
      },
    );
    await cubit.importFromDevice();
    expect(queue.single.id, _local.id);
    expect(cubit.state.message, contains('1 file gagal'));
    expect(cubit.state.tracks, hasLength(1));
    await cubit.close();
  });
}
