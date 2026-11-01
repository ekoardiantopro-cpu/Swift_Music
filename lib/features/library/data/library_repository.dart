import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LibraryRepository {
  Future<Set<String>> loadLikes();
  Future<void> saveLikes(Set<String> ids);
  Future<List<String>> loadRecent();
  Future<void> saveRecent(List<String> ids);
}

class LocalLibraryRepository implements LibraryRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<Set<String>> loadLikes() async =>
      (await _preferences.getStringList('liked_tracks') ?? []).toSet();
  @override
  Future<void> saveLikes(Set<String> ids) =>
      _preferences.setStringList('liked_tracks', ids.toList());
  @override
  Future<List<String>> loadRecent() async =>
      await _preferences.getStringList('recent_tracks') ?? [];
  @override
  Future<void> saveRecent(List<String> ids) =>
      _preferences.setStringList('recent_tracks', ids);
}
