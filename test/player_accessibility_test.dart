import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/library/data/library_repository.dart';
import 'package:swift_music/features/library/presentation/library_cubit.dart';
import 'package:swift_music/features/player/presentation/artwork_style_cubit.dart';
import 'package:swift_music/features/player/presentation/player_cubit.dart';
import 'package:swift_music/features/player/presentation/widgets/lyrics_panel.dart';
import 'package:swift_music/features/player/presentation/widgets/responsive_player.dart';

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

void main() {
  testWidgets(
    'lyrics remain readable at 200 percent text scale on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final style = ArtworkStyleCubit(
        load: () async => 'lyrics',
        save: (_) async {},
      );
      await style.select(ArtworkStyle.lyrics);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ArtworkStyleCubit>(create: (_) => style),
            BlocProvider<PlayerCubit>(
              create: (_) => PlayerCubit(
                BaseAudioHandler(),
                positionStream: const Stream.empty(),
              ),
            ),
            BlocProvider<LibraryCubit>(
              create: (_) => LibraryCubit(_MemoryLibrary()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ResponsivePlayer(
                state: const PlayerState(
                  item: MediaItem(id: 'local', title: 'Local music'),
                ),
                lyrics: 'Readable lyrics',
                position: 0,
                maximum: 120000,
                onSeekStart: (_) {},
                onSeekChanged: (_) {},
                onSeekEnd: (_) {},
                onVolume: () {},
                onArtwork: () {},
                onDevices: () {},
                onQueue: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('album-stage'))).width,
        greaterThanOrEqualTo(280),
      );
      final body = find.descendant(
        of: find.byType(LyricsPanel),
        matching: find.byType(SingleChildScrollView),
      );
      expect(tester.getSize(body).height, greaterThan(90));
      expect(find.text('Readable lyrics'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
