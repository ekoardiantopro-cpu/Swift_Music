import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/companion/data/watch_bridge.dart';

class _Handler extends BaseAudioHandler {
  final actions = <String>[];
  Duration? sought;
  double? volume;
  @override
  Future<void> play() async {
    actions.add('play');
  }

  @override
  Future<void> pause() async {
    actions.add('pause');
  }

  @override
  Future<void> skipToNext() async {
    actions.add('next');
  }

  @override
  Future<void> skipToPrevious() async {
    actions.add('previous');
  }

  @override
  Future<void> seek(Duration position) async {
    sought = position;
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    expect(name, 'setVolume');
    volume = extras!['volume'] as double;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'watch commands reach the real playback contract and validate inputs',
    () async {
      final handler = _Handler();
      handler.mediaItem.add(
        const MediaItem(
          id: 'secret-local-id',
          title: 'Song',
          artist: 'Artist',
          duration: Duration(seconds: 120),
          extras: {'url': 'file:///private/music.mp3'},
        ),
      );
      final bridge = WatchBridge(handler);
      for (final action in ['play', 'pause', 'next', 'previous']) {
        await bridge.command({'action': action});
      }
      expect(handler.actions, ['play', 'pause', 'next', 'previous']);
      await bridge.command({'action': 'seek', 'value': 12345});
      expect(handler.sought, const Duration(milliseconds: 12345));
      await bridge.command({'action': 'volume', 'value': .35});
      expect(handler.volume, .35);
      for (final invalid in [-1, 1.1, double.nan, double.infinity, 'loud']) {
        await expectLater(
          bridge.command({'action': 'volume', 'value': invalid}),
          throwsArgumentError,
        );
      }
      await expectLater(
        bridge.command({'action': 'seek', 'value': 120001}),
        throwsArgumentError,
      );
      await expectLater(
        bridge.command({'action': 'delete'}),
        throwsArgumentError,
      );
      final state = bridge.snapshot();
      expect(state['title'], 'Song');
      expect(state['durationMs'], 120000);
      expect(state.toString(), isNot(contains('private')));
      expect(state.toString(), isNot(contains('secret-local-id')));
      await bridge.close();
    },
  );
}
