import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import 'personal_cubit.dart';
import 'music_center_screen.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final personal = PersonalScope.maybeOf(context)!;
    final tracks = context.watch<CatalogCubit>().state.tracks;
    final artists = <String, (int, int)>{};
    for (final track in tracks) {
      final mark = personal.state.song(track.id);
      final previous = artists[track.artist] ?? (0, 0);
      artists[track.artist] = (
        previous.$1 + mark.number('plays'),
        previous.$2 + mark.number('listenedMs'),
      );
    }
    final ranked = artists.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final plays = personal.state.songs.values.fold<int>(
      0,
      (sum, mark) => sum + mark.number('plays'),
    );
    final milliseconds = personal.state.songs.values.fold<int>(
      0,
      (sum, mark) => sum + mark.number('listenedMs'),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik lokal')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.headphones),
            title: Text('$plays pemutaran'),
            subtitle: Text(
              '${(milliseconds / 3600000).toStringAsFixed(2)} jam mendengarkan',
            ),
          ),
          if (personal.state.flag('private'))
            const ListTile(
              leading: Icon(Icons.visibility_off),
              title: Text('Mode privasi aktif; statistik baru tidak dicatat'),
            ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Lagu teratas'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MusicCollectionPage(
                  kind: 'mostPlayed',
                  title: 'Lagu teratas',
                ),
              ),
            ),
          ),
          const ListTile(title: Text('Artis teratas')),
          for (final artist in ranked.take(30))
            ListTile(
              title: Text(artist.key),
              subtitle: Text(
                '${artist.value.$1} pemutaran • ${(artist.value.$2 / 60000).toStringAsFixed(1)} menit',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MusicCollectionPage(
                    kind: 'artist',
                    title: artist.key,
                    value: artist.key,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
