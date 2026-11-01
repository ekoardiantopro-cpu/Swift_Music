import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/player/domain/sleep_timer.dart';
import 'package:swift_music/features/player/data/playback_session_repository.dart';

class _Timer implements Timer {
  _Timer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    isActive = false;
    callback();
  }
}

void main() {
  test('loading a restored source cannot trigger end of track sleep', () async {
    var expired = 0;
    final sleep = SleepTimer(
      onExpire: () async {
        expired++;
      },
      onChanged: () {},
    );
    sleep.afterTrack('restored');
    await sleep.trackBoundary(
      loaded: false,
      playing: false,
      previouslyReady: false,
      sameItem: true,
    );
    await sleep.trackBoundary(
      loaded: true,
      playing: true,
      previouslyReady: false,
      sameItem: true,
    );
    expect(expired, 0);
    await sleep.trackBoundary(
      loaded: true,
      playing: true,
      previouslyReady: true,
      sameItem: false,
    );
    expect(expired, 0);
    expect(sleep.active, isTrue);
    await sleep.trackBoundary(
      loaded: true,
      playing: true,
      previouslyReady: true,
      sameItem: true,
    );
    expect(expired, 1);
    expect(sleep.active, isFalse);
    sleep.dispose();
  });
  test(
    'timer replacement and cancellation cannot expire a stale deadline',
    () async {
      final timers = <_Timer>[];
      var expired = 0;
      final sleep = SleepTimer(
        onExpire: () async {
          expired++;
        },
        onChanged: () {},
        schedule: (_, callback) {
          final timer = _Timer(callback);
          timers.add(timer);
          return timer;
        },
      );
      sleep.start(const Duration(minutes: 15));
      sleep.start(const Duration(minutes: 30));
      timers.first.fire();
      expect(expired, 0);
      timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(expired, 1);
      expect(sleep.active, isFalse);
      sleep.afterTrack('local');
      expect(sleep.trackId, 'local');
      await sleep.expire();
      expect(expired, 2);
      sleep.dispose();
    },
  );
  test('wall clock expiry works after delayed background callback', () async {
    var now = DateTime.utc(2026, 10, 30);
    var expired = false;
    final sleep = SleepTimer(
      now: () => now,
      onExpire: () async {
        expired = true;
      },
      onChanged: () {},
      schedule: (_, callback) => _Timer(callback),
    );
    sleep.start(const Duration(minutes: 15));
    now = now.add(const Duration(minutes: 16));
    expect(await sleep.expireIfDue(), isTrue);
    expect(expired, isTrue);
    expect(await sleep.expireIfDue(), isFalse);
    expect(() => sleep.start(Duration.zero), throwsArgumentError);
    sleep.dispose();
  });
  test(
    'session round trip preserves order and removes unavailable tracks safely',
    () {
      final original = PlaybackSession(
        ids: ['b', 'a', 'b', 'gone'],
        currentId: 'a',
        positionMs: 42000,
        volume: .6,
        shuffle: true,
        repeat: 'all',
      );
      final restored = PlaybackSession.fromJson(
        original.toJson(),
      ).reconcile({'a', 'b'});
      expect(restored.ids, ['b', 'a']);
      expect(restored.currentId, 'a');
      expect(restored.positionMs, 42000);
      expect(restored.volume, .6);
      expect(restored.shuffle, isTrue);
      expect(restored.repeat, 'all');
      final missing = original.reconcile({'b'});
      expect(missing.currentId, 'b');
      expect(missing.positionMs, 0);
      expect(original.reconcile({}).ids, isEmpty);
    },
  );
  test('invalid session schema fails and malformed numbers are bounded', () {
    expect(
      () => PlaybackSession.fromJson({'version': 9, 'ids': []}),
      throwsFormatException,
    );
    final restored = PlaybackSession.fromJson({
      'version': 1,
      'ids': ['a'],
      'currentId': 'a',
      'positionMs': -50,
      'volume': double.nan,
      'repeat': 'invalid',
    });
    expect(restored.positionMs, 0);
    expect(restored.volume, 1);
    expect(restored.repeat, 'none');
  });
}
