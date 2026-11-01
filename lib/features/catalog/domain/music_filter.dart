import 'track.dart';

class MusicFilter {
  const MusicFilter({
    this.folder,
    this.extension,
    this.artist,
    this.album,
    this.duration,
  });
  final String? folder, extension, artist, album, duration;
  bool get active => [
    folder,
    extension,
    artist,
    album,
    duration,
  ].any((value) => value != null);
  bool matches(Track track, {Set<String>? folderTracks}) {
    if (folder != null && !(folderTracks?.contains(track.id) ?? false)) {
      return false;
    }
    if (artist != null &&
        !track.artist.toLowerCase().contains(artist!.trim().toLowerCase())) {
      return false;
    }
    if (album != null &&
        !track.album.toLowerCase().contains(album!.trim().toLowerCase())) {
      return false;
    }
    if (extension != null &&
        Uri.tryParse(track.audioUrl)?.path.split('.').last.toLowerCase() !=
            extension) {
      return false;
    }
    final seconds = track.duration?.inSeconds;
    return switch (duration) {
      'short' => seconds != null && seconds <= 180,
      'long' => seconds != null && seconds > 180,
      'unknown' => seconds == null,
      _ => true,
    };
  }
}
