/// Domain entity: tidak bergantung pada Flutter atau engine audio.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.audioUrl,
    required this.artUrl,
    required this.lyrics,
    this.duration,
    this.info = const {},
    this.missing = false,
  });
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String audioUrl;
  final String artUrl;
  final String lyrics;
  final Duration? duration;
  final Map<String, dynamic> info;
  final bool missing;
  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? genre,
    String? artUrl,
    String? lyrics,
    Map<String, dynamic>? info,
    bool? missing,
  }) => Track(
    id: id,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    genre: genre ?? this.genre,
    audioUrl: audioUrl,
    artUrl: artUrl ?? this.artUrl,
    lyrics: lyrics ?? this.lyrics,
    duration: duration,
    info: info ?? this.info,
    missing: missing ?? this.missing,
  );
  bool get isLocal => Uri.tryParse(audioUrl)?.scheme == 'file';
}
