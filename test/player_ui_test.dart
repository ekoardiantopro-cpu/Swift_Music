import 'package:swift_music/features/library/presentation/playlist_cubit.dart';
import 'package:swift_music/features/library/data/playlist_repository.dart';
import 'package:swift_music/features/player/presentation/artwork_style_cubit.dart';
import 'package:swift_music/features/player/presentation/widgets/album_display.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/core/widgets/motion.dart';
import 'package:swift_music/app/main_screen.dart';
import 'package:swift_music/core/theme/app_theme.dart';
import 'package:swift_music/features/catalog/data/demo_catalog_repository.dart';
import 'package:swift_music/features/catalog/domain/catalog_repository.dart';
import 'package:swift_music/features/catalog/domain/track.dart';
import 'package:swift_music/features/catalog/presentation/catalog_cubit.dart';
import 'package:swift_music/features/library/data/library_repository.dart';
import 'package:swift_music/features/library/presentation/library_cubit.dart';
import 'package:swift_music/features/player/presentation/now_playing_screen.dart';
import 'package:swift_music/features/player/presentation/player_cubit.dart';
import 'package:swift_music/features/player/presentation/widgets/mini_player.dart';
import 'package:swift_music/features/player/presentation/widgets/lyrics_panel.dart';

class _MemoryLibrary implements LibraryRepository {
  @override
  Future<Set<String>> loadLikes() async => {};
  @override
  Future<List<String>> loadRecent() async => [];
  @override
  Future<void> saveLikes(Set<String> ids) async {}
  @override
  Future<void> saveRecent(List<String> ids) async {}
}

class _OfflineCatalog implements CatalogRepository {
  @override
  final List<Track> tracks = DemoCatalogRepository().tracks
      .map(
        (track) => Track(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          genre: track.genre,
          audioUrl: track.audioUrl,
          artUrl: '',
          lyrics: track.lyrics,
        ),
      )
      .toList();
  @override
  List<Track> search(String query, {String? genre}) => tracks
      .where(
        (track) =>
            (genre == null || track.genre == genre) &&
            track.title.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
}

void main() {
  testWidgets(
    'system Back pops pages, then returns tabs to Home before leaving',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Swift Music',
        packageName: 'com.swiftmusic.swift_music',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = _OfflineCatalog();
      final handler = BaseAudioHandler();
      handler.mediaItem.add(
        const MediaItem(id: 'demo-1', title: 'Midnight Bloom'),
      );
      await tester.pumpWidget(
        RepositoryProvider<CatalogRepository>.value(
          value: repository,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<PlaylistCubit>(
                create: (_) => PlaylistCubit(MemoryPlaylistRepository()),
              ),
              BlocProvider<ArtworkStyleCubit>(
                create: (_) => ArtworkStyleCubit(
                  load: () async => null,
                  save: (_) async {},
                ),
              ),
              BlocProvider<CatalogCubit>(
                create: (_) => CatalogCubit(repository),
              ),
              BlocProvider<PlayerCubit>(
                create: (_) =>
                    PlayerCubit(handler, positionStream: const Stream.empty()),
              ),
              BlocProvider<LibraryCubit>(
                create: (_) => LibraryCubit(_MemoryLibrary()),
              ),
            ],
            child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.library_music_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tentang Swift Music'));
      await tester.pumpAndSettle();
      expect(find.text('ekoardianto.pro@gmail.com'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your Library'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NowPlayingScreen), findsNothing);
      expect(find.text('Your Library'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your next favorite is waiting.'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your next favorite is waiting.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        platformCalls.where((call) => call == 'SystemNavigator.pop'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('Library imports local audio and displays it immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _OfflineCatalog();
    final handler = BaseAudioHandler();
    final queued = <Track>[];
    final catalog = CatalogCubit(
      repository,
      importAudio: () async {
        const track = Track(
          id: 'local-test',
          title: 'Offline track',
          artist: 'Lagu lokal',
          album: 'On this device',
          genre: 'Local',
          audioUrl: 'file:///music/offline.mp3',
          artUrl: '',
          lyrics: '',
        );
        repository.tracks.add(track);
        return [track];
      },
      onAdded: (tracks) async {
        queued.addAll(tracks);
      },
      importFolder: (progress, cancelled) async {
        progress(0, 0, 'Folder test');
        const track = Track(
          id: 'local-folder',
          title: 'Folder track',
          artist: 'Lagu lokal',
          album: 'On this device',
          genre: 'Local',
          audioUrl: 'file:///music/folder.wav',
          artUrl: '',
          lyrics: '',
        );
        repository.tracks.add(track);
        progress(1, 1, 'Folder test');
        return [track];
      },
    );
    await tester.pumpWidget(
      RepositoryProvider<CatalogRepository>.value(
        value: repository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlaylistCubit>(
              create: (_) => PlaylistCubit(MemoryPlaylistRepository()),
            ),
            BlocProvider<ArtworkStyleCubit>(
              create: (_) =>
                  ArtworkStyleCubit(load: () async => null, save: (_) async {}),
            ),
            BlocProvider<CatalogCubit>(create: (_) => catalog),
            BlocProvider<PlayerCubit>(
              create: (_) =>
                  PlayerCubit(handler, positionStream: const Stream.empty()),
            ),
            BlocProvider<LibraryCubit>(
              create: (_) => LibraryCubit(_MemoryLibrary()),
            ),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih lagu lokal'));
    await tester.pumpAndSettle();
    final libraryScroll = find.descendant(
      of: find.byKey(const Key('library-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Offline track'),
      180,
      scrollable: libraryScroll,
    );
    expect(find.text('Offline track'), findsOneWidget);
    expect(queued.single.isLocal, isTrue);
    tester.state<ScrollableState>(libraryScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih folder musik'));
    await tester.pumpAndSettle();
    expect(queued, hasLength(2));
    await tester.scrollUntilVisible(
      find.text('Folder track'),
      180,
      scrollable: libraryScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('Folder track'), findsOneWidget);
    await tester.tap(find.text('Artists'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Lagu lokal'),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('artist-groups')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Lagu lokal'));
    await tester.pumpAndSettle();
    expect(find.text('Folder track'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('mini player opens a usable full player on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handler = BaseAudioHandler();
    final player = PlayerCubit(handler, positionStream: const Stream.empty());
    final library = LibraryCubit(_MemoryLibrary());
    final catalog = _OfflineCatalog();
    final track = catalog.tracks.first;
    handler.mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        duration: const Duration(minutes: 4),
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider<CatalogRepository>.value(
        value: catalog,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlaylistCubit>(
              create: (_) => PlaylistCubit(MemoryPlaylistRepository()),
            ),
            BlocProvider<ArtworkStyleCubit>(
              create: (_) =>
                  ArtworkStyleCubit(load: () async => null, save: (_) async {}),
            ),
            BlocProvider<CatalogCubit>(create: (_) => CatalogCubit(catalog)),
            BlocProvider<PlayerCubit>(create: (_) => player),
            BlocProvider<LibraryCubit>(create: (_) => library),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const MainScreen()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    // Main controls fit without scrolling on phones, tablets and landscape.
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(800, 1280),
      const Size(844, 390),
      const Size(568, 320),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final controls = tester.getRect(
        find.byKey(const Key('transport-controls')),
      );
      expect(controls.top, greaterThanOrEqualTo(0), reason: '$size');
      expect(controls.bottom, lessThanOrEqualTo(size.height), reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 132, bottom: 102);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('transport-controls'))).bottom,
      lessThanOrEqualTo(810),
    );
    expect(
      tester.getRect(find.byKey(const Key('volume-trigger'))).top,
      greaterThanOrEqualTo(44),
    );
    tester.view.resetPadding();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('album-stage')));
    await tester.tap(find.byKey(const Key('album-stage')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tambah atau edit lirik'), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('album-stage'))).width,
      greaterThanOrEqualTo(280),
    );
    final lyricBody = find.descendant(
      of: find.byType(LyricsPanel),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(lyricBody).height, greaterThan(90));
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('album-stage')));
    await tester.tap(find.byKey(const Key('album-stage')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Tampilan album · Vinyl'), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-stage')));
    await tester.pumpAndSettle();
    expect(find.text('Tampilan album · Spectrum'), findsOneWidget);
    await tester.tap(find.byKey(const Key('album-stage')));
    await tester.pumpAndSettle();
    expect(find.text('Tampilan album · Wave'), findsOneWidget);
    await tester.tap(find.text('Tampilan album · Wave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cover'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tampilan album · Cover'));
    await tester.tap(find.text('Tampilan album · Cover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vinyl'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlbumDisplay>(find.byType(AlbumDisplay)).style,
      ArtworkStyle.vinyl,
    );
    await tester.tap(find.text('Tampilan album · Vinyl'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pulse'));
    await tester.tap(find.text('Pulse'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlbumDisplay>(find.byType(AlbumDisplay)).style,
      ArtworkStyle.pulse,
    );
    expect(find.byKey(const Key('seek-slider')), findsOneWidget);
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    final artworkBeforeVolume = tester.getRect(
      find.byKey(const Key('album-stage')),
    );
    await tester.ensureVisible(find.byTooltip('Atur volume'));
    await tester.tap(find.byTooltip('Atur volume'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('volume-slider')), findsOneWidget);
    final volumeBounds = tester.getRect(
      find.byKey(const Key('volume-overlay')),
    );
    expect(volumeBounds.left, lessThan(24));
    expect(volumeBounds.height, greaterThan(volumeBounds.width * 2));
    final hold = await tester.startGesture(tester.getCenter(find.text('100%')));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const Key('volume-slider')), findsOneWidget);
    await hold.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('album-stage'))),
      artworkBeforeVolume,
    );
    final visualizer = find.descendant(
      of: find.byType(NowPlayingScreen),
      matching: find.byType(EqualizerVisualizer),
    );
    expect(tester.getSize(visualizer).width, greaterThan(200));
    await tester.ensureVisible(find.byTooltip('Volume turun'));
    await tester.tap(find.byTooltip('Volume turun'));
    await tester.pumpAndSettle();
    expect(player.state.volume, closeTo(.95, .001));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    await tester.tap(find.byTooltip('Atur volume'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    await tester.tap(find.byTooltip('Atur volume'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Tutup volume'));
    await tester.tap(find.byTooltip('Tutup volume'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    expect(player.state.volume, closeTo(.95, .001));
    await tester.tap(find.byTooltip('Atur volume'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bisukan'));
    await tester.pumpAndSettle();
    expect(player.state.volume, 0);
    await tester.tap(find.byTooltip('Aktifkan suara'));
    await tester.pumpAndSettle();
    expect(player.state.volume, closeTo(.95, .001));
    await tester.tap(find.byKey(const Key('volume-dismiss-area')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Sukai lagu'));
    await tester.tap(find.byTooltip('Sukai lagu'));
    await tester.pump();
    expect(library.state.likes, contains(track.id));
    await tester.ensureVisible(find.text('This device · Demo'));
    await tester.tap(find.text('This device · Demo'));
    await tester.pumpAndSettle();
    expect(find.text('Connect to a device'), findsOneWidget);
    expect(find.text('Demo · tidak tersambung'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
