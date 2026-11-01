import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/player/presentation/artwork_style_cubit.dart';
import 'package:swift_music/features/player/presentation/widgets/album_display.dart';

void main() {
  test(
    'rapid taps cycle immediately and persist the latest selection in order',
    () async {
      final gate = Completer<void>();
      final writes = <String>[];
      final cubit = ArtworkStyleCubit(
        load: () async => null,
        save: (value) async {
          writes.add(value);
          await gate.future;
        },
      );
      final first = cubit.next();
      expect(cubit.state.style, ArtworkStyle.lyrics);
      await cubit.next();
      await cubit.next();
      expect(cubit.state.style, ArtworkStyle.spectrum);
      gate.complete();
      await first;
      expect(writes, ['lyrics', 'spectrum']);
      await cubit.next();
      await cubit.next();
      await cubit.next();
      expect(cubit.state.style, ArtworkStyle.cover);
      expect(writes.last, 'cover');
      await cubit.close();
    },
  );
  test(
    'explicit Cover selection wins over a delayed saved Vinyl preference',
    () async {
      final load = Completer<String?>();
      String? saved;
      final cubit = ArtworkStyleCubit(
        load: () => load.future,
        save: (value) async {
          saved = value;
        },
      );
      await cubit.select(ArtworkStyle.cover);
      load.complete('vinyl');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.style, ArtworkStyle.cover);
      expect(saved, 'cover');
      await cubit.close();
    },
  );
  test(
    'selection survives a new Cubit and a slow restore cannot overwrite it',
    () async {
      String? saved;
      final load = Completer<String?>();
      final first = ArtworkStyleCubit(
        load: () => load.future,
        save: (value) async {
          saved = value;
        },
      );
      await first.select(ArtworkStyle.vinyl);
      load.complete('cover');
      await Future<void>.delayed(Duration.zero);
      expect(first.state.style, ArtworkStyle.vinyl);
      expect(saved, 'vinyl');
      await first.close();
      final second = ArtworkStyleCubit(
        load: () async => saved,
        save: (_) async {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(second.state.style, ArtworkStyle.vinyl);
      await second.close();
    },
  );

  test(
    'invalid preferences use cover; save failure keeps choice with a visible error',
    () async {
      final cubit = ArtworkStyleCubit(
        load: () async => 'unknown',
        save: (_) async {
          throw StateError('disk');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.style, ArtworkStyle.cover);
      await cubit.select(ArtworkStyle.pulse);
      expect(cubit.state.style, ArtworkStyle.pulse);
      expect(cubit.state.saving, isFalse);
      expect(cubit.state.error, isNotNull);
      await cubit.close();
    },
  );

  testWidgets('vinyl and pulse animate only with active accessible playback', (
    tester,
  ) async {
    Future<void> show(
      ArtworkStyle style, {
      bool playing = true,
      bool reduced = false,
      bool visible = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: visible,
              child: Center(
                child: AlbumDisplay(
                  url: '',
                  size: 240,
                  style: style,
                  playing: playing,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    for (final style in [
      ArtworkStyle.vinyl,
      ArtworkStyle.pulse,
      ArtworkStyle.spectrum,
      ArtworkStyle.wave,
    ]) {
      await show(style);
      expect(tester.hasRunningAnimations, isTrue);
      if (style == ArtworkStyle.vinyl) {
        expect(
          tester.getSize(find.byType(RotationTransition)),
          const Size(240, 240),
        );
      }
      await show(style, playing: false);
      expect(tester.hasRunningAnimations, isFalse);
      await show(style, reduced: true);
      expect(tester.hasRunningAnimations, isFalse);
      await show(style, visible: false);
      expect(tester.hasRunningAnimations, isFalse);
      await show(style);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
    }
    await show(ArtworkStyle.cover);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
