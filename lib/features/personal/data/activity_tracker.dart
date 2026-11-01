import 'dart:async';
import 'package:audio_service/audio_service.dart';
import '../presentation/personal_cubit.dart';

/// Measures listening time with a stopwatch; seeks never inflate statistics.
class ActivityTracker {
  ActivityTracker(this.handler, this.personal) {
    _subscriptions.add(
      personal.stream
          .map((state) => state.flag('private'))
          .distinct()
          .listen((_) => _watch.reset()),
    );
    _subscriptions.add(handler.mediaItem.listen((_) => _sync()));
    _subscriptions.add(
      handler.playbackState.listen((state) {
        if (state.errorMessage != null && handler.mediaItem.value != null) {
          unawaited(
            personal.mark(handler.mediaItem.value!.id, {
              'problem': state.errorMessage,
            }),
          );
        }
        _sync();
      }),
    );
  }
  final AudioHandler handler;
  final PersonalCubit personal;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _watch = Stopwatch();
  String? _id, _lastCounted;
  Timer? _timer;
  bool _playing = false;
  DateTime _lastCountedAt = DateTime.fromMillisecondsSinceEpoch(0);
  void _flush() {
    final elapsed = _watch.elapsedMilliseconds;
    _watch.reset();
    if (_id != null && elapsed > 0) unawaited(personal.listened(_id!, elapsed));
  }

  void _sync() {
    final id = handler.mediaItem.value?.id;
    final state = handler.playbackState.value;
    final playing =
        state.playing &&
        state.processingState == AudioProcessingState.ready &&
        handler.mediaItem.value?.extras?['network'] != true &&
        id != null;
    if (id == _id && playing == _playing) return;
    _flush();
    _id = id;
    _playing = playing;
    if (playing) {
      if (_lastCounted != id ||
          (state.updatePosition < const Duration(seconds: 2) &&
              DateTime.now().difference(_lastCountedAt) >
                  const Duration(seconds: 30))) {
        _lastCounted = id;
        _lastCountedAt = DateTime.now();
        unawaited(personal.recordPlay(id));
      }
      if (personal.state.song(id).text('problem').isNotEmpty) {
        unawaited(personal.mark(id, {'problem': ''}));
      }
      _watch.start();
      _timer ??= Timer.periodic(const Duration(seconds: 10), (_) => _flush());
    } else {
      _watch.stop();
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> dispose() async {
    _flush();
    _timer?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
  }
}
