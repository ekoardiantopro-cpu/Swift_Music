import '../../catalog/domain/track.dart';

class SongMark {
  SongMark({Map<String, dynamic> values = const {}})
    : values = Map.unmodifiable(values);
  final Map<String, dynamic> values;
  String text(String key) => values[key] is String ? values[key] as String : '';
  int number(String key) =>
      values[key] is num ? (values[key] as num).toInt() : 0;
  bool flag(String key) => values[key] == true;
  List<Map<String, dynamic>> get bookmarks =>
      (values['bookmarks'] as List? ?? [])
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
  SongMark update(Map<String, dynamic> change) =>
      SongMark(values: {...values, ...change});
  Track apply(Track track) {
    String? override(String key) =>
        text(key).trim().isEmpty ? null : text(key).trim();
    return track.copyWith(
      title: override('title'),
      artist: override('artist'),
      album: override('album'),
      genre: override('genre'),
      artUrl: override('cover'),
      lyrics: override('lyrics'),
      info: {
        ...track.info,
        for (final key in [
          'composer',
          'writer',
          'year',
          'label',
          'bpm',
          'key',
          'disc',
          'track',
        ])
          if (text(key).isNotEmpty) key: text(key),
      },
    );
  }
}

class PersonalState {
  PersonalState({
    Map<String, dynamic> settings = const {},
    Map<String, SongMark> songs = const {},
    List<Map<String, dynamic>> queues = const [],
    List<String> searches = const [],
    List<Map<String, dynamic>> savedSearches = const [],
    this.error,
  }) : settings = Map.unmodifiable(settings),
       songs = Map.unmodifiable(songs),
       queues = List.unmodifiable(queues),
       searches = List.unmodifiable(searches),
       savedSearches = List.unmodifiable(savedSearches);
  final Map<String, dynamic> settings;
  final Map<String, SongMark> songs;
  final List<Map<String, dynamic>> queues, savedSearches;
  final List<String> searches;
  final String? error;
  SongMark song(String id) => songs[id] ?? SongMark();
  bool flag(String key) => settings[key] == true;
  String text(String key, [String fallback = '']) =>
      settings[key] is String ? settings[key] as String : fallback;
  double value(String key, double fallback) =>
      settings[key] is num ? (settings[key] as num).toDouble() : fallback;
  Map<String, dynamic> toJson() => {
    'settings': settings,
    'songs': songs.map((id, mark) => MapEntry(id, mark.values)),
    'queues': queues,
    'searches': searches,
    'savedSearches': savedSearches,
  };
  static PersonalState fromJson(Map<String, dynamic> json) => PersonalState(
    settings: Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
    songs: (json['songs'] as Map? ?? {}).map(
      (key, value) => MapEntry(
        key as String,
        SongMark(values: Map<String, dynamic>.from(value as Map)),
      ),
    ),
    queues: (json['queues'] as List? ?? [])
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList(),
    searches: (json['searches'] as List? ?? []).whereType<String>().toList(),
    savedSearches: (json['savedSearches'] as List? ?? [])
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList(),
  );
}
