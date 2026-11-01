import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/music_personalization.dart';

abstract interface class PersonalRepository {
  Future<PersonalState> load();
  Future<void> save(PersonalState state);
}

class LocalPersonalRepository implements PersonalRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<PersonalState> load() async {
    final raw = await _preferences.getString('music_personal_v1');
    return raw == null
        ? PersonalState()
        : PersonalState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(PersonalState state) =>
      _preferences.setString('music_personal_v1', jsonEncode(state.toJson()));
}

class MemoryPersonalRepository implements PersonalRepository {
  PersonalState state = PersonalState();
  @override
  Future<PersonalState> load() async => state;
  @override
  Future<void> save(PersonalState state) async {
    this.state = state;
  }
}
