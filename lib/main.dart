import 'package:audio_service/audio_service.dart';
import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app/main_screen.dart';
import 'core/theme/app_theme.dart';
import 'features/catalog/domain/catalog_repository.dart';
import 'features/catalog/data/device_catalog_repository.dart';
import 'features/catalog/data/local_audio_store.dart';
import 'features/catalog/data/audio_metadata_reader.dart';
import 'features/catalog/data/folder_registry.dart';
import 'features/library/data/playlist_repository.dart';
import 'features/library/presentation/playlist_cubit.dart';
import 'app/catalog_lifecycle.dart';
import 'features/catalog/presentation/catalog_cubit.dart';
import 'features/library/data/library_repository.dart';
import 'features/library/presentation/library_cubit.dart';
import 'features/player/data/swift_audio_handler.dart';
import 'features/player/presentation/player_cubit.dart';
import 'features/player/presentation/artwork_style_cubit.dart';
import 'features/personal/presentation/personal_cubit.dart';
import 'features/personal/domain/music_personalization.dart';
import 'features/personal/data/personal_repository.dart';
import 'features/personal/data/personal_assets.dart';
import 'features/personal/data/activity_tracker.dart';
import 'core/widgets/music_keyboard.dart';
import 'features/companion/data/watch_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 128;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memuat koleksi musik…'),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    final support = await getApplicationSupportDirectory();
    final personal = PersonalCubit(LocalPersonalRepository());
    await personal.initialize();
    final catalog = DeviceCatalogRepository(
      LocalAudioStore(
        Directory(p.join(support.path, 'local_music')),
        metadata: const NativeAudioMetadataReader(),
      ),
      registry: FileFolderRegistry(
        File(p.join(support.path, 'music_sources.json')),
      ),
    );
    catalog.decorate = personal.resolve;
    await catalog.initialize();
    final handler = await AudioService.init<SwiftAudioHandler>(
      builder: SwiftAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.swiftmusic.app.playback',
        androidNotificationChannelName: 'Swift Music playback',
        androidNotificationOngoing: false,
        androidNotificationIcon: 'drawable/ic_stat_music_note',
        // Memungkinkan resume dari background tanpa memulai ulang foreground service.
        // Service/notifikasi bertahan saat pause; tombol Stop mengakhirinya.
        androidStopForegroundOnPause: false,
      ),
    );
    // Konfigurasikan setelah plugin audio diinisialisasi.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    handler.configureCatalog(catalog.tracks);
    await handler.restoreSession();
    await handler.applyPreferences(personal.state.toJson());
    WatchBridge(handler).start();
    personal.onSettingsChanged = () =>
        handler.applyPreferences(personal.state.toJson());
    final library = LibraryCubit(LocalLibraryRepository());
    final playlists = PlaylistCubit(LocalPlaylistRepository());
    await library.initialize();
    final catalogState = CatalogCubit(
      catalog,
      importAudio: catalog.importFromDevice,
      importFolder: catalog.importFolder,
      summary: () => catalog.lastImportSummary,
      folders: () => catalog.savedFolders,
      rescan: catalog.rescanFolder,
      forget: catalog.forgetFolder,
      setAutoScan: catalog.setAutoScan,
      repair: catalog.repairTrack,
      onRepaired: () => handler.refreshMetadata(catalog.tracks),
      removeTrack: (id) async {
        await handler.removeCatalogTrack(id);
        await catalog.removeTrack(id);
      },
      onRemoved: (id) async {
        await library.removeTrack(id);
        await playlists.removeTrackEverywhere(id);
      },
      onAdded: handler.appendTracks,
    );
    personal.onCatalogChanged = () async {
      catalogState.refresh();
      await handler.refreshMetadata(catalog.tracks);
    };
    ActivityTracker(handler, personal);
    handler.onQueueHistory = (ids, current, position) => personal.saveQueue(
      'Sesi ${DateTime.now().toLocal().toString().split('.').first}',
      ids,
      currentId: current,
      positionMs: position.inMilliseconds,
      history: true,
    );
    runApp(
      SwiftMusicApp(
        catalog: catalog,
        handler: handler,
        library: library,
        playlists: playlists,
        personal: personal,
        assets: PersonalAssets(
          Directory(p.join(support.path, 'personal_assets')),
        ),
        catalogCubit: catalogState,
      ),
    );
  } catch (error, stack) {
    debugPrint('Swift Music initialization failed: $error\n$stack');
    runApp(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Audio service gagal dimulai. Periksa konfigurasi native '
                  'pada README, lalu jalankan kembali aplikasi.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SwiftMusicApp extends StatelessWidget {
  const SwiftMusicApp({
    super.key,
    required this.catalog,
    required this.handler,
    required this.library,
    required this.playlists,
    required this.catalogCubit,
    required this.personal,
    required this.assets,
    this.positionStream,
  });
  final CatalogRepository catalog;
  final AudioHandler handler;
  final Stream<Duration>? positionStream;
  final LibraryCubit library;
  final PlaylistCubit playlists;
  final CatalogCubit catalogCubit;
  final PersonalCubit personal;
  final PersonalAssets assets;

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider<PersonalAssets>.value(
        value: assets,
        child: RepositoryProvider<CatalogRepository>.value(
          value: catalog,
          child: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => ArtworkStyleCubit()),
              BlocProvider<PersonalCubit>(create: (_) => personal),
              BlocProvider<CatalogCubit>(create: (_) => catalogCubit),
              BlocProvider<LibraryCubit>(create: (_) => library),
              BlocProvider<PlaylistCubit>(create: (_) => playlists),
              BlocProvider<PlayerCubit>(
                create: (_) =>
                    PlayerCubit(handler, positionStream: positionStream),
              ),
            ],
            child: BlocBuilder<PersonalCubit, PersonalState>(
              builder: (context, personalState) => PersonalScope(
                controller: personal,
                state: personalState,
                child: MaterialApp(
                  title: 'Swift Music',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.accent(
                    personalState.value('accent', 0xFF1DB954).toInt(),
                  ),
                  builder: (context, child) => MultiBlocListener(
                    listeners: [
                      BlocListener<PersonalCubit, PersonalState>(
                        listenWhen: (before, after) =>
                            after.error != null && before.error != after.error,
                        listener: (context, state) => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(state.error!))),
                      ),
                      BlocListener<PlaylistCubit, PlaylistState>(
                        listenWhen: (previous, current) =>
                            current.error != null &&
                            previous.error != current.error,
                        listener: (context, state) => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(state.error!))),
                      ),
                      BlocListener<CatalogCubit, CatalogState>(
                        listenWhen: (previous, current) =>
                            current.message != null &&
                            previous.message != current.message,
                        listener: (context, state) => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(state.message!))),
                      ),
                      BlocListener<PlayerCubit, PlayerState>(
                        listenWhen: (previous, current) =>
                            previous.error != current.error,
                        listener: (context, state) {
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.clearSnackBars();
                          if (state.error != null) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(state.error!)),
                            );
                          }
                        },
                      ),
                      BlocListener<PlayerCubit, PlayerState>(
                        listenWhen: (previous, current) =>
                            current.playing &&
                            current.item != null &&
                            (!previous.playing ||
                                previous.item?.id != current.item?.id),
                        listener: (context, state) {
                          if (!personal.state.flag('private') &&
                              state.item?.extras?['network'] != true) {
                            unawaited(
                              context.read<LibraryCubit>().recordPlay(
                                state.item!.id,
                              ),
                            );
                          }
                        },
                      ),
                      BlocListener<LibraryCubit, LibraryState>(
                        listenWhen: (previous, current) =>
                            current.error != null &&
                            previous.error != current.error,
                        listener: (context, state) => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(state.error!))),
                      ),
                    ],
                    child: MusicKeyboard(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                  home: const CatalogLifecycle(child: MainScreen()),
                ),
              ),
            ),
          ),
        ),
      );
}
