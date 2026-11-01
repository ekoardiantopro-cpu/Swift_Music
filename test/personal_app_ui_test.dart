import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/main.dart';
import 'package:swift_music/features/catalog/domain/catalog_repository.dart';
import 'package:swift_music/features/catalog/domain/track.dart';
import 'package:swift_music/features/catalog/data/demo_catalog_repository.dart';
import 'package:swift_music/features/catalog/presentation/catalog_cubit.dart';
import 'package:swift_music/features/library/data/library_repository.dart';
import 'package:swift_music/features/library/presentation/library_cubit.dart';
import 'package:swift_music/features/library/data/playlist_repository.dart';
import 'package:swift_music/features/library/presentation/playlist_cubit.dart';
import 'package:swift_music/features/personal/data/personal_repository.dart';
import 'package:swift_music/features/personal/data/personal_assets.dart';
import 'package:swift_music/features/personal/presentation/personal_cubit.dart';

class _Catalog implements CatalogRepository {
  @override
  final tracks = DemoCatalogRepository().tracks
      .map((track) => track.copyWith(artUrl: ''))
      .toList();
  @override
  List<Track> search(String query, {String? genre}) => tracks
      .where(
        (t) =>
            t.title.toLowerCase().contains(query.toLowerCase()) &&
            (genre == null || t.genre == genre),
      )
      .toList();
}

class _Library implements LibraryRepository {
  @override
  Future<Set<String>> loadLikes() async => {};
  @override
  Future<List<String>> loadRecent() async => [];
  @override
  Future<void> saveLikes(Set<String> ids) async {}
  @override
  Future<void> saveRecent(List<String> ids) async {}
}

void main() {
  testWidgets(
    'application settings apply motion and accent through production composition',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'swift-personal-ui-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final personal = PersonalCubit(MemoryPersonalRepository());
      await personal.initialize();
      final catalog = _Catalog();
      final handler = BaseAudioHandler();
      handler.mediaItem.add(
        const MediaItem(id: 'demo-1', title: 'Midnight Bloom'),
      );
      final library = LibraryCubit(_Library());
      await library.initialize();
      await tester.pumpWidget(
        SwiftMusicApp(
          catalog: catalog,
          handler: handler,
          library: library,
          playlists: PlaylistCubit(MemoryPlaylistRepository()),
          catalogCubit: CatalogCubit(catalog),
          personal: personal,
          assets: PersonalAssets(directory),
          positionStream: const Stream.empty(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Music Center'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Penuh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nonaktif').last);
      await tester.pumpAndSettle();
      expect(personal.state.text('motion'), 'off');
      await tester.tap(find.byTooltip('Aksen ff52c7f2'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .primary,
        const Color(0xFF52C7F2),
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open Stream').hitTestable(), findsNothing);
      await tester.tap(find.byIcon(Icons.library_music_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Open Stream').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Open Stream'));
      await tester.pumpAndSettle();
      expect(find.text('Private Playback'), findsOneWidget);
      final open = find.byKey(const Key('open-source-action'));
      await tester.scrollUntilVisible(
        open,
        160,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Masukkan URL stream lengkap dengan protokol dan alamat server.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Aktifkan sumber'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Spotify'));
      await tester.pumpAndSettle();
      expect(personal.state.settings['source_spotify'], false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
