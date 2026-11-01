import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/player/presentation/widgets/lyrics_panel.dart';

void main() {
  testWidgets(
    'LRC follows playback and long press seeks without consuming taps',
    (tester) async {
      Duration? sought;
      Future<void> show(Duration position) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 400,
              child: LyricsPanel(
                trackId: 'lrc',
                title: 'Timed',
                fallback: '[00:00]First\n[00:05]Second\n[00:10]Third',
                position: position,
                onSeek: (value) => sought = value,
                load: (_) async => null,
              ),
            ),
          ),
        ),
      );
      await show(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      final second = find.ancestor(
        of: find.text('Second'),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      expect(
        tester.widget<AnimatedDefaultTextStyle>(second.first).style.color,
        const Color(0xFF1DB954),
      );
      await tester.longPress(find.text('Second'));
      expect(sought, const Duration(seconds: 5));
      await show(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      final third = find.ancestor(
        of: find.text('Third'),
        matching: find.byType(AnimatedDefaultTextStyle),
      );
      expect(
        tester.widget<AnimatedDefaultTextStyle>(third.first).style.color,
        const Color(0xFF1DB954),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'custom lyrics save by track and restore without claiming synchronization',
    (tester) async {
      final saved = <String, String>{};
      Future<void> show(String id) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 320,
                child: LyricsPanel(
                  key: ValueKey(id),
                  trackId: id,
                  title: 'Lagu $id',
                  fallback: 'Lirik belum tersedia.',
                  load: (id) async => saved[id],
                  save: (id, text) async {
                    saved[id] = text;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await show('a');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tambah atau edit lirik'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Baris pertama\nBaris kedua',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      expect(saved['a'], 'Baris pertama\nBaris kedua');
      expect(find.text('Baris pertama\nBaris kedua'), findsOneWidget);
      await show('b');
      await tester.pumpAndSettle();
      expect(find.text('Lirik belum tersedia.'), findsOneWidget);
      await show('a');
      await tester.pumpAndSettle();
      expect(find.text('Baris pertama\nBaris kedua'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
