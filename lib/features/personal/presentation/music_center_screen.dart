import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/track_tile.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/domain/music_filter.dart';
import '../../catalog/domain/fuzzy_search.dart';
import 'statistics_screen.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import 'personal_cubit.dart';
import 'personal_dialogs.dart';
import 'song_details_screen.dart';
import 'personal_settings_screen.dart';
import 'car_mode_screen.dart';
import '../../library/presentation/playlist_tools_screen.dart';
import '../../library/presentation/bulk_tracks_screen.dart';

class MusicCenterScreen extends StatelessWidget {
  const MusicCenterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = PersonalScope.maybeOf(context)!;
    final state = scope.state;
    final songs = context.watch<CatalogCubit>().state.tracks;
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Center'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => open(const PersonalSettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Pilih banyak lagu'),
            onTap: () => open(const BulkTracksScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('Folder & gabung playlist'),
            onTap: () => open(const PlaylistFoldersScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.directions_car_outlined),
            title: const Text('Mode berkendara'),
            onTap: () => open(const CarModeScreen()),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Mode privasi'),
            subtitle: const Text(
              'Hentikan pencatatan riwayat, pencarian dan statistik',
            ),
            value: state.flag('private'),
            onChanged: (v) => scope.controller.setting('private', v),
          ),
          ListTile(
            leading: const Icon(Icons.query_stats),
            title: const Text('Statistik mendengarkan'),
            subtitle: Text(
              '${state.songs.values.fold<int>(0, (n, mark) => n + mark.number('plays'))} pemutaran • ${(state.songs.values.fold<int>(0, (n, mark) => n + mark.number('listenedMs')) / 3600000).toStringAsFixed(1)} jam',
            ),
            onTap: () => open(const StatisticsScreen()),
          ),
          for (final entry in const {
            'mostPlayed': 'Paling sering diputar',
            'newest': 'Baru ditambahkan',
            'unheard': 'Belum pernah diputar',
            'rediscover': 'Dengarkan kembali',
            'rated': 'Rating 4–5 bintang',
            'pinned': 'Disematkan',
            'timeline': 'Linimasa rilisan',
          }.entries)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(entry.value),
              onTap: () => open(
                MusicCollectionPage(kind: entry.key, title: entry.value),
              ),
            ),
          for (final group in ['mood', 'version'])
            ExpansionTile(
              title: Text(group == 'mood' ? 'Mood' : 'Versi lagu'),
              children: [
                for (final name
                    in songs
                        .map(
                          (song) => state
                              .song(song.id)
                              .text(group == 'mood' ? 'mood' : 'versionGroup'),
                        )
                        .where((name) => name.isNotEmpty)
                        .toSet())
                  ListTile(
                    title: Text(name),
                    onTap: () => open(
                      MusicCollectionPage(
                        kind: group,
                        title: name,
                        value: name,
                      ),
                    ),
                  ),
              ],
            ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Antrean tersimpan & riwayat sesi'),
            onTap: () => open(const SavedQueuesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Riwayat & pencarian tersimpan'),
            onTap: () => open(const SearchNotebookScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.bookmarks_outlined),
            title: const Text('Penanda & catatan lagu'),
            onTap: () => open(
              const MusicCollectionPage(
                kind: 'annotated',
                title: 'Penanda & catatan',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.quiz_outlined),
            title: const Text('Kuis musik koleksi sendiri'),
            onTap: songs.length < 2
                ? null
                : () => open(const MusicQuizScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.report_problem_outlined),
            title: const Text('Lagu bermasalah'),
            onTap: () => open(
              const MusicCollectionPage(
                kind: 'problems',
                title: 'Lagu bermasalah',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MusicCollectionPage extends StatelessWidget {
  const MusicCollectionPage({
    super.key,
    required this.kind,
    required this.title,
    this.value = '',
  });
  final String kind, title, value;
  @override
  Widget build(BuildContext context) {
    final personal = PersonalScope.maybeOf(context)!;
    var tracks = personal.controller.collection(
      kind,
      context.watch<CatalogCubit>().state.tracks,
      value: value,
    );
    if (kind == 'annotated') {
      tracks = tracks
          .where(
            (t) =>
                personal.state.song(t.id).bookmarks.isNotEmpty ||
                personal.state.song(t.id).text('notes').isNotEmpty,
          )
          .toList();
    }
    if (kind == 'problems') {
      tracks = tracks
          .where(
            (t) =>
                t.missing ||
                personal.state.song(t.id).text('problem').isNotEmpty,
          )
          .toList();
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => context.read<PlayerCubit>().playCollection(
                      tracks.map((t) => t.id).toList(),
                    ),
              icon: const Icon(Icons.play_arrow),
              label: Text('Putar ${tracks.length} lagu'),
            ),
          ),
          Expanded(
            child: tracks.isEmpty
                ? const Center(child: Text('Belum ada lagu untuk koleksi ini.'))
                : ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, index) =>
                        kind == 'annotated' || kind == 'problems'
                        ? ListTile(
                            title: Text(tracks[index].title),
                            subtitle: Text(
                              kind == 'problems'
                                  ? (tracks[index].missing
                                        ? 'File tidak ditemukan'
                                        : personal.state
                                              .song(tracks[index].id)
                                              .text('problem'))
                                  : personal.state
                                        .song(tracks[index].id)
                                        .text('notes'),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    SongDetailsScreen(track: tracks[index]),
                              ),
                            ),
                          )
                        : TrackTile(track: tracks[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class SavedQueuesScreen extends StatelessWidget {
  const SavedQueuesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final personal = PersonalScope.maybeOf(context)!;
    final player = context.watch<PlayerCubit>();
    final available = context
        .watch<CatalogCubit>()
        .state
        .tracks
        .map((t) => t.id)
        .toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('Antrean dan riwayat')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('Simpan antrean sekarang'),
            onTap: player.state.queueItems.isEmpty
                ? null
                : () async {
                    final name = await askMusicText(
                      context,
                      'Nama antrean',
                      maxLength: 80,
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await personal.controller.saveQueue(
                        name,
                        player.state.queueItems.map((i) => i.id).toList(),
                        currentId: player.state.item?.id,
                        positionMs: player.state.position.inMilliseconds,
                      );
                    }
                  },
          ),
          for (final queue in personal.state.queues)
            ListTile(
              leading: Icon(
                queue['history'] == true ? Icons.history : Icons.queue_music,
              ),
              title: Text(queue['name'] as String),
              subtitle: Text(
                '${(queue['ids'] as List).where(available.contains).length} lagu tersedia',
              ),
              onTap: () => player.restoreQueue(
                (queue['ids'] as List).cast<String>(),
                currentId: queue['currentId'] as String?,
                positionMs: queue['positionMs'] as int? ?? 0,
              ),
              trailing: IconButton(
                tooltip: 'Hapus antrean tersimpan',
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    personal.controller.deleteQueue(queue['at'] as int),
              ),
            ),
        ],
      ),
    );
  }
}

class SearchNotebookScreen extends StatefulWidget {
  const SearchNotebookScreen({super.key});
  @override
  State<SearchNotebookScreen> createState() => _SearchNotebookScreenState();
}

class _SearchNotebookScreenState extends State<SearchNotebookScreen> {
  String? _query;
  Map<String, dynamic> _filters = {};
  @override
  Widget build(BuildContext context) {
    final personal = PersonalScope.maybeOf(context)!;
    final catalog = context.watch<CatalogCubit>().state;
    final tracks = catalog.tracks;
    final filter = MusicFilter(
      folder: _filters['folder'] as String?,
      extension: _filters['extension'] as String?,
      artist: _filters['artist'] as String?,
      album: _filters['album'] as String?,
      duration: _filters['duration'] as String?,
    );
    final folder = catalog.sources
        .where((source) => source.id == filter.folder)
        .firstOrNull;
    final folderTracks = folder?.fingerprints.values
        .map((value) => value.split('|').last)
        .toSet();
    final query = (_query ?? '').trim().toLowerCase();
    final results = tracks
        .where(
          (t) =>
              FuzzyMusicSearch.score(query, '${t.title} ${t.artist}') != null ||
              '${t.lyrics} ${personal.state.song(t.id).text('notes')}'
                  .toLowerCase()
                  .contains(query),
        )
        .where(
          (t) =>
              filter.matches(t, folderTracks: folderTracks) &&
              (_filters['genre'] == null || t.genre == _filters['genre']),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pencarian tersimpan'),
        actions: [
          IconButton(
            tooltip: 'Hapus riwayat pencarian',
            onPressed: () => personal.controller.clearSearches(),
            icon: const Icon(Icons.history_toggle_off),
          ),
        ],
      ),
      body: _query == null
          ? ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Simpan pencarian baru'),
                  onTap: () async {
                    final text = await askMusicText(
                      context,
                      'Judul, artis atau potongan lirik',
                    );
                    if (text != null && text.trim().isNotEmpty) {
                      await personal.controller.saveSearch(text);
                    }
                  },
                ),
                for (final item in personal.state.savedSearches)
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(
                      item['name'] as String? ?? item['query'] as String,
                    ),
                    onTap: () => setState(() {
                      _query = item['query'] as String;
                      _filters = Map<String, dynamic>.from(
                        item['filters'] as Map? ?? {},
                      );
                    }),
                  ),
                for (final q in personal.state.searches)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(q),
                    onTap: () => setState(() {
                      _query = q;
                      _filters = {};
                    }),
                  ),
              ],
            )
          : Column(
              children: [
                ListTile(
                  title: Text(_query!),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _query = null),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) => TrackTile(track: results[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

class MusicQuizScreen extends StatefulWidget {
  const MusicQuizScreen({super.key});
  @override
  State<MusicQuizScreen> createState() => _MusicQuizScreenState();
}

class _MusicQuizScreenState extends State<MusicQuizScreen> {
  final _random = Random();
  List<Track> _options = [];
  Track? _answer;
  String? _result;
  int _correct = 0, _rounds = 0;
  PlayerCubit? _player;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = context.read<PlayerCubit>();
  }

  @override
  void dispose() {
    unawaited(_player?.cancelPreview());
    super.dispose();
  }

  void _next(List<Track> tracks) {
    _options = ([...tracks]..shuffle(_random)).take(4).toList();
    _answer = _options[_random.nextInt(_options.length)];
    _result = null;
  }

  @override
  Widget build(BuildContext context) {
    final tracks = context
        .watch<CatalogCubit>()
        .state
        .tracks
        .where((t) => !t.missing)
        .toList();
    if (tracks.length < 2) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Tambahkan minimal dua lagu.')),
      );
    }
    if (_answer == null) _next(tracks);
    final player = context.watch<PlayerCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tebak lagu')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Skor $_correct / $_rounds'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => player.state.previewId != null
                ? player.cancelPreview()
                : player.preview(_answer!.id),
            icon: const Icon(Icons.headphones),
            label: Text(
              player.state.previewId != null
                  ? 'Hentikan cuplikan'
                  : 'Dengarkan cuplikan',
            ),
          ),
          for (final option in _options)
            OutlinedButton(
              onPressed: _result != null
                  ? null
                  : () => setState(() {
                      _rounds++;
                      if (option.id == _answer!.id) {
                        _correct++;
                        _result = 'Benar!';
                      } else {
                        _result = 'Jawaban: ${_answer!.title}';
                      }
                    }),
              child: Text(option.title),
            ),
          if (_result != null) Text(_result!),
          TextButton(
            onPressed: () => setState(() => _next(tracks)),
            child: const Text('Pertanyaan berikutnya'),
          ),
        ],
      ),
    );
  }
}
