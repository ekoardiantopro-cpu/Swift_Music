import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../catalog/domain/music_filter.dart';
import 'search_filters.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../personal/presentation/personal_dialogs.dart';
import '../../streaming/presentation/source_icons.dart';
import '../../streaming/presentation/streaming_screen.dart';
import 'service_search_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String? _genre;
  MusicFilter _filter = const MusicFilter();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CatalogCubit>().state;
    final catalog = context.read<CatalogRepository>();
    final folder = state.sources
        .where((source) => source.id == _filter.folder)
        .firstOrNull;
    final folderTracks = folder?.fingerprints.values
        .map((value) => value.split('|').last)
        .toSet();
    final results = catalog
        .search(_controller.text, genre: _genre)
        .where((track) => _filter.matches(track, folderTracks: folderTracks))
        .toList();
    final filtering =
        _controller.text.trim().isNotEmpty || _genre != null || _filter.active;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Discover',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          onSubmitted: (query) =>
              PersonalScope.maybeOf(context)?.controller.search(query),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Judul lagu atau artis',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: PersonalScope.maybeOf(context) != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Simpan pencarian dan filter',
                        icon: const Icon(Icons.bookmark_add_outlined),
                        onPressed: !filtering
                            ? null
                            : () async {
                                final personal = PersonalScope.maybeOf(
                                  context,
                                )!.controller;
                                final name = await askMusicText(
                                  context,
                                  'Nama pencarian',
                                  initial: _controller.text.isEmpty
                                      ? 'Filter koleksi'
                                      : _controller.text,
                                  maxLength: 80,
                                );
                                if (name != null) {
                                  await personal.saveSearch(
                                    _controller.text,
                                    name: name,
                                    filters: {
                                      'genre': _genre,
                                      'folder': _filter.folder,
                                      'extension': _filter.extension,
                                      'artist': _filter.artist,
                                      'album': _filter.album,
                                      'duration': _filter.duration,
                                    },
                                  );
                                }
                              },
                      ),
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Hapus pencarian',
                          onPressed: () => setState(_controller.clear),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  )
                : _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: () => setState(_controller.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        SearchFilters(
          filter: _filter,
          tracks: state.tracks,
          folders: state.sources,
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        const SizedBox(height: 16),
        if (_genre != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(_genre!),
              onDeleted: () => setState(() => _genre = null),
            ),
          ),
        AnimatedSwitcher(
          duration: motionDuration(context),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            filtering ? 'Search results' : 'Browse all',
            key: ValueKey(filtering),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),
        if (!filtering)
          _ServiceCards(
            onTap: (source) => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StreamingScreen(initial: source),
              ),
            ),
            onTvDigital: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const StreamingScreen(tvDigital: true),
              ),
            ),
          ),
      ],
    );
    // Build result rows on demand rather than retaining the whole collection.
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 1 + (filtering ? (results.isEmpty ? 1 : results.length) : 0),
      itemBuilder: (context, index) {
        if (index == 0) return header;
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Tidak ada lagu yang cocok.'),
          );
        }
        final track = results[index - 1];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TrackTile(track: track),
            Padding(
              padding: const EdgeInsets.only(left: 64, bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_android,
                    size: 14,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Lokal',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cari “${track.title}” di YouTube Music',
                    visualDensity: VisualDensity.compact,
                    icon: const SourceIcon(MusicSource.youtube, size: 18),
                    onPressed: () => _openService(
                      context,
                      MusicSource.youtube,
                      '${track.title} ${track.artist}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cari “${track.title}” di Spotify',
                    visualDensity: VisualDensity.compact,
                    icon: const SourceIcon(MusicSource.spotify, size: 18),
                    onPressed: () => _openService(
                      context,
                      MusicSource.spotify,
                      '${track.title} ${track.artist}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _openService(BuildContext context, MusicSource source, String query) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ServiceSearchScreen(source: source, query: query),
      ),
    );
  }
}

class _ServiceCards extends StatelessWidget {
  const _ServiceCards({required this.onTap, required this.onTvDigital});
  final ValueChanged<MusicSource> onTap;
  final VoidCallback onTvDigital;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _ServiceCard(
              source: MusicSource.spotify,
              title: 'Spotify',
              subtitle: 'Musik dan playlist',
              color: const Color(0xFF176B46),
              onTap: () => onTap(MusicSource.spotify),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ServiceCard(
              source: MusicSource.youtube,
              title: 'YouTube Music',
              subtitle: 'Trending dan rekomendasi',
              color: const Color(0xFF9F1830),
              onTap: () => onTap(MusicSource.youtube),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _ServiceCard(
        source: MusicSource.network,
        title: 'IPTV · Open Stream',
        subtitle: 'Playlist channel TV lewat internet atau jaringan lokal',
        color: const Color(0xFF2852A0),
        onTap: () => onTap(MusicSource.network),
        wide: true,
      ),
      const SizedBox(height: 12),
      _ServiceCard(
        source: MusicSource.network,
        title: 'TV Digital',
        subtitle: 'Siaran antena melalui tuner lokal · tanpa internet',
        color: const Color(0xFF16765B),
        onTap: onTvDigital,
        icon: Icons.live_tv_rounded,
        wide: true,
      ),
    ],
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.wide = false,
    this.icon,
  });
  final MusicSource source;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool wide;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: wide ? 88 : 132,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(
                    children: [
                      if (icon != null)
                        Icon(icon, size: 34, color: Colors.white)
                      else
                        const SourceIcon(MusicSource.network, size: 34),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SourceIcon(source, size: 30),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}
