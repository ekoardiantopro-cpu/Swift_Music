import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackSession {
  PlaybackSession({
    required Iterable<String> ids,
    required this.currentId,
    this.positionMs = 0,
    this.volume = 1,
    this.shuffle = false,
    this.repeat = 'none',
    this.speed = 1,
  }) : ids = List.unmodifiable(ids.toSet());
  final List<String> ids;
  final String? currentId;
  final int positionMs;
  final double volume;
  final bool shuffle;
  final String repeat;
  final double speed;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'ids': ids,
    'currentId': currentId,
    'positionMs': positionMs,
    'volume': volume,
    'shuffle': shuffle,
    'repeat': repeat,
    'speed': speed,
  };
  static PlaybackSession fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['ids'] is! List) {
      throw const FormatException('Sesi tidak valid.');
    }
    final rawPosition = json['positionMs'];
    final rawVolume = json['volume'];
    return PlaybackSession(
      ids: (json['ids'] as List).whereType<String>(),
      currentId: json['currentId'] is String
          ? json['currentId'] as String
          : null,
      positionMs: rawPosition is num && rawPosition.isFinite
          ? rawPosition.toInt().clamp(0, 86400000)
          : 0,
      volume: rawVolume is num && rawVolume.isFinite
          ? rawVolume.toDouble().clamp(0, 1)
          : 1,
      shuffle: json['shuffle'] == true,
      repeat: ['none', 'one', 'all'].contains(json['repeat'])
          ? json['repeat'] as String
          : 'none',
      speed: json['speed'] is num && (json['speed'] as num).isFinite
          ? (json['speed'] as num).toDouble().clamp(.5, 2)
          : 1,
    );
  }

  PlaybackSession reconcile(Set<String> available) {
    final kept = ids.where(available.contains).toList();
    final selected = kept.contains(currentId) ? currentId : kept.firstOrNull;
    return PlaybackSession(
      ids: kept,
      currentId: selected,
      positionMs: selected == currentId ? positionMs : 0,
      volume: volume,
      shuffle: shuffle,
      repeat: repeat,
      speed: speed,
    );
  }
}

abstract interface class PlaybackSessionRepository {
  Future<PlaybackSession?> load();
  Future<void> save(PlaybackSession session);
}

class LocalPlaybackSessionRepository implements PlaybackSessionRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<PlaybackSession?> load() async {
    final raw = await _preferences.getString('playback_session_v1');
    return raw == null
        ? null
        : PlaybackSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(PlaybackSession session) => _preferences.setString(
    'playback_session_v1',
    jsonEncode(session.toJson()),
  );
}
