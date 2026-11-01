import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/data/local_audio_store.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../about/presentation/about_screen.dart';
import 'library_cubit.dart';
import 'playlist_cubit.dart';
import 'library_sections.dart';
import 'collection_screens.dart';
import 'track_actions.dart';
import 'backup_screen.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../personal/presentation/music_center_screen.dart';
import '../../streaming/presentation/streaming_screen.dart';
import '../../streaming/presentation/source_icons.dart';
import '../../player/presentation/player_cubit.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  void _importMenu(BuildContext context) {
    final catalog = context.read<CatalogCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (PersonalScope.maybeOf(context) != null)
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('Music Center'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const MusicCenterScreen(),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Cadangkan / pulihkan koleksi'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Buat playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final id = await createPlaylist(context);
                if (id != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistScreen(id: id),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Folder musik'),
              subtitle: const Text('Termasuk musik di dalam subfolder'),
              onTap: () {
                Navigator.pop(sheetContext);
                catalog.importFromFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('File audio'),
              onTap: () {
                Navigator.pop(sheetContext);
                catalog.importFromDevice();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    final personal = PersonalScope.maybeOf(context);
    final player = context.read<PlayerCubit>();
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your Library',
                    maxLines: 2,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Tentang Swift Music',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
                IconButton(
                  tooltip: 'Impor lagu dari perangkat',
                  onPressed: catalog.importing
                      ? null
                      : () => _importMenu(context),
                  icon: const Icon(Icons.file_upload_outlined),
                ),
              ],
            ),
          ),
          if (personal != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _ServiceCard(
                      source: MusicSource.youtube,
                      enabled:
                          personal.state.settings['source_youtube'] != false,
                      onChanged: (value) async {
                        await personal.controller.setting(
                          'source_youtube',
                          value,
                        );
                        if (!value) await player.returnLocal();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ServiceCard(
                      source: MusicSource.spotify,
                      enabled:
                          personal.state.settings['source_spotify'] != false,
                      onChanged: (value) async {
                        await personal.controller.setting(
                          'source_spotify',
                          value,
                        );
                        if (!value) await player.returnLocal();
                      },
                    ),
                  ),
                ],
              ),
            ),
          TabBar(
            isScrollable: MediaQuery.textScalerOf(context).scale(14) > 18,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Albums'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _LocalCollection(),
                _GroupList(byArtist: true),
                _GroupList(byArtist: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  final MusicSource source;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = source == MusicSource.spotify
        ? const Color(0xFF1DB954)
        : const Color(0xFFFF1744);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return PressScale(
      child: AnimatedContainer(
        duration: motionDuration(context, 360),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? accent.withValues(alpha: .12)
              : const Color(0xFF232229),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? accent.withValues(alpha: .42)
                : Colors.white.withValues(alpha: .06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SourceIcon(source, size: 26, selected: enabled),
                const Spacer(),
                AnimatedSwitcher(
                  duration: motionDuration(context, 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    enabled ? Icons.check_circle : Icons.pause_circle_outline,
                    key: ValueKey(enabled),
                    size: 20,
                    color: enabled ? accent : AppTheme.secondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * scale),
            Text(
              source == MusicSource.youtube ? 'YouTube Music' : 'Spotify',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: motionDuration(context, 240),
              child: Text(
                enabled ? 'Enabled' : 'Disabled',
                key: ValueKey(('state', enabled)),
                style: TextStyle(
                  color: enabled ? accent : AppTheme.secondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Switch.adaptive(value: enabled, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalCollection extends StatelessWidget {
  const _LocalCollection();
  void _formats(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format musik',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text('File yang dapat dipilih untuk dicoba diputar:'),
            Wrap(
              spacing: 8,
              children: LocalAudioStore.extensions
                  .map((ext) => Chip(label: Text(ext.toUpperCase())))
                  .toList(),
            ),
            const Text(
              'Kemampuan putar bergantung pada codec dan perangkat. MP3, AAC/M4A dan WAV adalah pilihan umum. '
              'WMA, APE, DSD, MIDI dan file berproteksi DRM belum didukung. Mengganti ekstensi tidak mengubah format audio.',
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    final collections = context.watch<PlaylistCubit>();
    final local = collections.sorted(
      catalog.tracks.where((track) => track.isLocal),
    );
    final library = context.watch<LibraryCubit>().state;
    final liked = catalog.tracks
        .where((track) => library.likes.contains(track.id))
        .toList();
    return CustomScrollView(
      key: const ValueKey('library-scroll'),
      slivers: [
        if (PersonalScope.maybeOf(context) != null)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Streaming',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SourceShortcuts(),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Lagu di perangkat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pilih folder beserta subfolder, atau beberapa file audio.',
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: catalog.importing
                      ? null
                      : () => context.read<CatalogCubit>().importFromFolder(),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Pilih folder musik'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: catalog.importing
                      ? null
                      : () => context.read<CatalogCubit>().importFromDevice(),
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('Pilih lagu lokal'),
                ),
                if (catalog.importing) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: catalog.total > 0
                        ? catalog.completed / catalog.total
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    catalog.total > 0
                        ? '${catalog.completed}/${catalog.total} · ${catalog.folder}'
                        : 'Memindai ${catalog.folder ?? 'pilihan musik'}…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton(
                    onPressed: catalog.cancelling
                        ? null
                        : () => context.read<CatalogCubit>().cancelImport(),
                    child: Text(
                      catalog.cancelling ? 'Menghentikan…' : 'Hentikan impor',
                    ),
                  ),
                ],
                TextButton.icon(
                  onPressed: () => _formats(context),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Lihat format musik'),
                ),
                const Text(
                  'Lagu disalin ke penyimpanan aplikasi agar tetap tersedia secara offline.',
                  style: TextStyle(color: AppTheme.secondary, fontSize: 11),
                ),
                if (local.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Belum ada lagu lokal. Pilih folder atau file musik Anda.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (catalog.sources.isNotEmpty)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Folder tersimpan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: catalog.sources.length,
            itemBuilder: (_, i) => SavedFolderCard(folder: catalog.sources[i]),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: PlaylistsHeading()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: collections.state.playlists.length,
            itemBuilder: (_, i) =>
                UserPlaylistCard(playlist: collections.state.playlists[i]),
          ),
        ),
        if (collections.state.playlists.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Buat playlist untuk mengatur koleksi Anda.',
                style: TextStyle(color: AppTheme.secondary),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Material(
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackCollectionScreen(
                      title: 'Liked Songs',
                      liked: true,
                    ),
                  ),
                ),
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF403078), Color(0xFF213F37)],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.favorite,
                        color: AppTheme.green,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Liked Songs',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text('${liked.length} lagu'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Semua lagu lokal (${local.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const LibrarySortButton(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.builder(
            itemCount: local.length,
            itemBuilder: (_, index) => TrackTile(track: local[index]),
          ),
        ),
      ],
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.byArtist});
  final bool byArtist;
  @override
  Widget build(BuildContext context) {
    final tracks = context.watch<CatalogCubit>().state.tracks;
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      (groups[byArtist ? track.artist : track.album] ??= []).add(track);
    }
    final entries = groups.entries.toList();
    return ListView.builder(
      key: ValueKey(byArtist ? 'artist-groups' : 'album-groups'),
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(byArtist ? Icons.person_outline : Icons.album_outlined),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} songs'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TrackCollectionScreen(
                title: entry.key,
                artist: byArtist ? entry.key : null,
                album: byArtist ? null : entry.key,
              ),
            ),
          ),
        );
      },
    );
  }
}
