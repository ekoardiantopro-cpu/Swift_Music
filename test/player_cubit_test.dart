import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/player/presentation/player_cubit.dart';

class FakeAudioHandler extends BaseAudioHandler {
  final calls = <String>[];
  bool failPlay = false;
  bool failVolume = false;
  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
  }

  @override
  Future<void> skipToNext() async {
    calls.add('next');
  }

  @override
  Future<void> skipToPrevious() async {
    calls.add('previous');
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    playbackState.add(playbackState.value.copyWith(shuffleMode: mode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: mode));
  }

  final volumes = <double>[];
  Completer<void>? volumeGate;
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'setVolume') {
      final volume = extras!['volume'] as double;
      volumes.add(volume);
      await volumeGate?.future;
      if (failVolume) throw StateError('volume unavailable');
      customState.add({'volume': volume});
    }
    return null;
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    calls.add('select:$index');
    mediaItem.add(MediaItem(id: 'track-$index', title: 'Track $index'));
  }

  @override
  Future<void> play() async {
    if (failPlay) throw StateError('network unavailable');
    calls.add('play');
    playbackState.add(
      PlaybackState(playing: true, processingState: AudioProcessingState.ready),
    );
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playbackState.add(
      PlaybackState(
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
  }
}

void main() {
  test(
    'empty queue clears selected song instead of retaining a deleted mini player',
    () async {
      final handler = FakeAudioHandler();
      final cubit = PlayerCubit(handler, positionStream: const Stream.empty());
      handler.mediaItem.add(
        const MediaItem(
          id: 'local',
          title: 'Local',
          duration: Duration(seconds: 90),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.item?.id, 'local');
      handler.queue.add([]);
      handler.mediaItem.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.item, isNull);
      expect(cubit.state.duration, Duration.zero);
      expect(cubit.state.playing, isFalse);
      await cubit.close();
    },
  );
  test(
    'seek, skip, shuffle and all repeat modes use the shared audio handler',
    () async {
      final handler = FakeAudioHandler();
      final player = PlayerCubit(handler, positionStream: const Stream.empty());
      await player.seek(const Duration(seconds: 30));
      await player.next();
      await player.previous();
      expect(handler.calls, ['seek:30000', 'next', 'previous']);
      await player.toggleShuffle();
      await Future<void>.delayed(Duration.zero);
      expect(player.state.shuffle, isTrue);
      await player.toggleShuffle();
      await Future<void>.delayed(Duration.zero);
      expect(player.state.shuffle, isFalse);
      for (final mode in [
        AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.one,
        AudioServiceRepeatMode.none,
      ]) {
        await player.cycleRepeat();
        await Future<void>.delayed(Duration.zero);
        expect(player.state.repeat, mode);
      }
      await player.close();
    },
  );
  test(
    'volume clamps, rejects non-finite values and restores mute level',
    () async {
      final handler = FakeAudioHandler();
      final player = PlayerCubit(handler, positionStream: const Stream.empty());
      await player.setVolume(2);
      expect(player.state.volume, 1);
      await player.setVolume(double.nan);
      expect(handler.volumes, [1]);
      await player.setVolume(.4);
      await player.toggleMute();
      expect(player.state.volume, 0);
      await player.toggleMute();
      expect(player.state.volume, .4);
      await player.adjustVolume(-2);
      expect(player.state.volume, 0);
      await player.close();
    },
  );

  test('rapid volume gestures serialize and keep the final target', () async {
    final handler = FakeAudioHandler()..volumeGate = Completer<void>();
    final player = PlayerCubit(handler, positionStream: const Stream.empty());
    final operation = player.setVolume(.2);
    await player.setVolume(.4);
    await player.setVolume(.8);
    expect(handler.volumes, [.2]);
    expect(player.state.volume, .8);
    handler.volumeGate!.complete();
    await operation;
    await Future<void>.delayed(Duration.zero);
    expect(handler.volumes, [.2, .8]);
    expect(player.state.volume, .8);
    handler.failVolume = true;
    await player.setVolume(.1);
    expect(player.state.volume, .8);
    expect(player.state.error, isNotNull);
    await player.close();
  });

  test(
    'selection precedes playback and player follows handler metadata',
    () async {
      final handler = FakeAudioHandler();
      final cubit = PlayerCubit(handler, positionStream: const Stream.empty());
      await cubit.playTrack(3);
      await Future<void>.delayed(Duration.zero);
      expect(handler.calls, ['select:3', 'play']);
      expect(cubit.state.item?.id, 'track-3');
      expect(cubit.state.playing, isTrue);
      await cubit.togglePlay();
      await Future<void>.delayed(Duration.zero);
      expect(handler.calls.last, 'pause');
      expect(cubit.state.playing, isFalse);
      await cubit.close();
    },
  );

  test('track change resets position and unknown duration', () async {
    final handler = FakeAudioHandler();
    final positions = StreamController<Duration>();
    final cubit = PlayerCubit(handler, positionStream: positions.stream);
    handler.mediaItem.add(
      const MediaItem(id: 'a', title: 'A', duration: Duration(minutes: 4)),
    );
    positions.add(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.position, const Duration(seconds: 30));
    handler.mediaItem.add(const MediaItem(id: 'b', title: 'B'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.position, Duration.zero);
    expect(cubit.state.duration, Duration.zero);
    await cubit.close();
    await positions.close();
  });

  test(
    'loading and service errors are reflected and retry clears errors',
    () async {
      final handler = FakeAudioHandler();
      final cubit = PlayerCubit(handler, positionStream: const Stream.empty());
      handler.playbackState.add(
        PlaybackState(processingState: AudioProcessingState.buffering),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.loading, isTrue);
      handler.playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.error,
          errorCode: 1,
          errorMessage: 'network unavailable',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.error, 'network unavailable');
      await cubit.togglePlay();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.error, isNull);
      expect(cubit.state.playing, isTrue);
      await cubit.close();
    },
  );

  test('command failure does not throw to the UI', () async {
    final handler = FakeAudioHandler()..failPlay = true;
    final cubit = PlayerCubit(handler, positionStream: const Stream.empty());
    await cubit.togglePlay();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });

  test(
    'closing Cubit cancels subscriptions without stopping the service',
    () async {
      final handler = FakeAudioHandler();
      final cubit = PlayerCubit(handler, positionStream: const Stream.empty());
      await cubit.close();
      handler.mediaItem.add(const MediaItem(id: 'later', title: 'Later'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.item, isNull);
      expect(handler.calls, isEmpty);
    },
  );
}
