import '../domain/catalog_repository.dart';
import '../domain/track.dart';

/// Judul/kategori adalah metadata demo, bukan metadata rekaman komersial.
class DemoCatalogRepository implements CatalogRepository {
  static const _names = [
    'Midnight Bloom',
    'Electric Heart',
    'Slow Sunday',
    'Velvet Skies',
    'After Hours',
    'Golden Coast',
  ];
  static const _artists = [
    'SoundHelix · Demo 1',
    'SoundHelix · Demo 2',
    'SoundHelix · Demo 3',
    'SoundHelix · Demo 4',
    'SoundHelix · Demo 5',
    'SoundHelix · Demo 6',
  ];
  static const _genres = ['Pop', 'Electronic', 'Jazz', 'R&B', 'Rock', 'Chill'];
  static const _photos = [
    'photo-1519681393784-d120267933ba',
    'photo-1470225620780-dba8ba36b745',
    'photo-1516280440614-37939bbacd81',
    'photo-1500530855697-b586d89ba3ee',
    'photo-1493225457124-a3eb161ffa5f',
    'photo-1476514525535-07fb3b4ae5f1',
  ];

  @override
  final List<Track> tracks = List.unmodifiable(
    List.generate(
      6,
      (i) => Track(
        id: 'demo-${i + 1}',
        title: _names[i],
        artist: _artists[i],
        album: ['Night Drive', 'Neon Dreams', 'Sunday Sessions'][i % 3],
        genre: _genres[i],
        audioUrl:
            'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${i + 1}.mp3',
        artUrl:
            'https://images.unsplash.com/${_photos[i]}?w=800&auto=format&fit=crop&q=80',
        lyrics:
            'INSTRUMENTAL DEMO\n\nRekaman contoh SoundHelix.\n'
            'Tidak tersedia lirik untuk lagu ini.\n\n'
            'Area ini siap menampilkan lirik dari katalog Anda.\n'
            'Lirik belum disinkronkan dengan waktu pemutaran.',
      ),
    ),
  );

  @override
  List<Track> search(String query, {String? genre}) {
    final normalized = query.trim().toLowerCase();
    return tracks
        .where(
          (t) =>
              (genre == null || t.genre == genre) &&
              '${t.title} ${t.artist}'.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }
}
