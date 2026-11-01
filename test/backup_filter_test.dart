import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/library/data/collection_backup.dart';
import 'package:swift_music/features/library/data/playlist_repository.dart';
import 'package:swift_music/features/library/domain/music_playlist.dart';
import 'package:swift_music/features/library/presentation/playlist_cubit.dart';
import 'package:swift_music/features/catalog/domain/music_filter.dart';
import 'package:swift_music/features/catalog/domain/track.dart';

void main() {
  test(
    'backup round trip retains missing song labels and merges without overwriting',
    () async {
      final backup = CollectionBackup(
        playlists: [
          MusicPlaylist(
            id: 'old',
            name: 'Morning',
            trackIds: ['demo-1'],
            trackLabels: {'demo-1': 'Song — Artist'},
          ),
        ],
        likes: {'demo-1'},
      );
      final decoded = CollectionBackup.decode(backup.encode());
      expect(decoded.playlists.single.trackLabels['demo-1'], 'Song — Artist');
      expect(decoded.likes, {'demo-1'});
      final cubit = PlaylistCubit(MemoryPlaylistRepository());
      final existing = await cubit.create('Existing');
      expect(await cubit.mergeBackup(decoded.playlists), 1);
      expect(await cubit.mergeBackup(decoded.playlists), 0);
      expect(cubit.state.playlists.first.id, existing);
      expect(cubit.state.playlists.last.id, isNot('old'));
      await cubit.close();
    },
  );
  test(
    'backup rejects unsupported schema, invalid track refs and oversized input',
    () {
      expect(
        () => CollectionBackup.decode('{}'.codeUnits),
        throwsFormatException,
      );
      final invalid = CollectionBackup(
        playlists: [],
        likes: {'file:///private/music.mp3'},
      );
      expect(() => invalid.encode(), throwsFormatException);
      expect(
        () => CollectionBackup.decode(
          List.filled(CollectionBackup.maxBytes + 1, 32),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'music filters combine folder, extension, artist, album and duration',
    () {
      const track = Track(
        id: 'local-id',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        genre: 'Jazz',
        audioUrl: 'file:///music/song.FLAC',
        artUrl: '',
        lyrics: '',
        duration: Duration(seconds: 200),
      );
      const filter = MusicFilter(
        folder: 'folder',
        extension: 'flac',
        artist: 'Artist',
        album: 'Album',
        duration: 'long',
      );
      expect(filter.matches(track, folderTracks: {'local-id'}), isTrue);
      expect(filter.matches(track, folderTracks: {}), isFalse);
      expect(const MusicFilter(duration: 'short').matches(track), isFalse);
      expect(const MusicFilter(duration: 'unknown').matches(track), isFalse);
      expect(const MusicFilter(artist: 'Other').matches(track), isFalse);
      expect(const MusicFilter().matches(track), isTrue);
    },
  );
}
