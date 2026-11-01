import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/library/data/library_repository.dart';
import 'package:swift_music/features/library/presentation/library_cubit.dart';

class MemoryLibrary implements LibraryRepository {
  Set<String> likes = {};
  List<String> recent = [];
  bool failWrites = false;
  @override
  Future<Set<String>> loadLikes() async => {...likes};
  @override
  Future<List<String>> loadRecent() async => [...recent];
  @override
  Future<void> saveLikes(Set<String> ids) async {
    if (failWrites) throw StateError('disk unavailable');
    likes = {...ids};
  }

  @override
  Future<void> saveRecent(List<String> ids) async {
    if (failWrites) throw StateError('disk unavailable');
    recent = [...ids];
  }
}

void main() {
  test('likes can be toggled and restored from storage', () async {
    final repository = MemoryLibrary();
    final cubit = LibraryCubit(repository);
    await cubit.initialize();
    await cubit.toggleLike('demo-1');
    final restored = LibraryCubit(repository);
    await restored.initialize();
    expect(restored.state.likes, {'demo-1'});
    await restored.toggleLike('demo-1');
    expect(repository.likes, isEmpty);
    await cubit.close();
    await restored.close();
  });
  test('recent plays are unique, newest first, and limited to six', () async {
    final cubit = LibraryCubit(MemoryLibrary());
    for (var i = 0; i < 8; i++) {
      await cubit.recordPlay('track-$i');
    }
    await cubit.recordPlay('track-4');
    expect(cubit.state.recent, [
      'track-4',
      'track-7',
      'track-6',
      'track-5',
      'track-3',
      'track-2',
    ]);
    await cubit.close();
  });
  test(
    'storage failure is visible and does not discard in-session likes',
    () async {
      final repository = MemoryLibrary()..failWrites = true;
      final cubit = LibraryCubit(repository);
      await cubit.toggleLike('demo-1');
      expect(cubit.state.likes, contains('demo-1'));
      expect(cubit.state.error, isNotNull);
      await cubit.close();
    },
  );
}
