import 'dart:async';

/// Owned by the audio service, so closing the player screen never cancels it.
class SleepTimer {
  SleepTimer({
    required this.onExpire,
    required this.onChanged,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? schedule,
  }) : _now = now ?? DateTime.now,
       _schedule = schedule ?? Timer.new;
  final Future<void> Function() onExpire;
  final void Function() onChanged;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _schedule;
  Timer? _timer;
  DateTime? deadline;
  String? trackId;
  int _revision = 0;
  bool get active => deadline != null || trackId != null;
  Map<String, dynamic> get json => {
    'deadlineMs': deadline?.millisecondsSinceEpoch,
    'trackId': trackId,
  };

  void start(Duration duration) {
    if (duration <= Duration.zero || duration > const Duration(hours: 24)) {
      throw ArgumentError('Durasi timer tidak valid.');
    }
    cancel();
    deadline = _now().add(duration);
    final revision = _revision;
    _timer = _schedule(duration, () {
      if (revision == _revision) unawaited(expire());
    });
    onChanged();
  }

  void afterTrack(String id) {
    cancel();
    trackId = id;
    onChanged();
  }

  void cancel() {
    _revision++;
    _timer?.cancel();
    _timer = null;
    deadline = null;
    trackId = null;
    onChanged();
  }

  Future<void> expire() async {
    if (!active) return;
    cancel();
    await onExpire();
  }

  Future<bool> expireIfDue() async {
    if (deadline != null && !_now().isBefore(deadline!)) {
      await expire();
      return true;
    }
    return false;
  }

  Future<void> trackBoundary({
    required bool loaded,
    required bool playing,
    required bool previouslyReady,
    required bool sameItem,
  }) async {
    if (trackId != null && loaded && playing && previouslyReady && sameItem) {
      await expire();
    }
  }

  void dispose() {
    _revision++;
    _timer?.cancel();
  }
}
