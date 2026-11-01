import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PlayerState {
  const PlayerState({
    this.item,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = AudioServiceRepeatMode.none,
    this.error,
    this.volume = 1,
    this.queueItems = const [],
    this.sleep = const {},
    this.speed = 1,
    this.previewId,
    this.canUndoQueue = false,
  });
  final MediaItem? item;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final AudioServiceRepeatMode repeat;
  final String? error;
  final double volume;
  final List<MediaItem> queueItems;
  final Map<String, dynamic> sleep;
  final double speed;
  final String? previewId;
  final bool canUndoQueue;
  bool get sleepActive =>
      sleep['deadlineMs'] != null || sleep['trackId'] != null;

  PlayerState copyWith({
    MediaItem? item,
    bool clearItem = false,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    AudioServiceRepeatMode? repeat,
    String? error,
    bool clearError = false,
    double? volume,
    List<MediaItem>? queueItems,
    Map<String, dynamic>? sleep,
    double? speed,
    String? previewId,
    bool clearPreview = false,
    bool? canUndoQueue,
  }) => PlayerState(
    item: clearItem ? null : item ?? this.item,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    shuffle: shuffle ?? this.shuffle,
    repeat: repeat ?? this.repeat,
    error: clearError ? null : error ?? this.error,
    volume: volume ?? this.volume,
    queueItems: queueItems ?? this.queueItems,
    sleep: sleep ?? this.sleep,
    speed: speed ?? this.speed,
    previewId: clearPreview ? null : previewId ?? this.previewId,
    canUndoQueue: canUndoQueue ?? this.canUndoQueue,
  );
}

class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit(this._handler, {Stream<Duration>? positionStream})
    : super(const PlayerState()) {
    _subscriptions.add(
      _handler.queue.listen((items) {
        if (!isClosed) {
          emit(state.copyWith(queueItems: List.unmodifiable(items)));
        }
      }),
    );
    _subscriptions.add(
      _handler.customState.listen((value) {
        if (value is Map && !isClosed) {
          if (value['canUndoQueue'] is bool) {
            emit(state.copyWith(canUndoQueue: value['canUndoQueue'] as bool));
          }
          if (value.containsKey('previewId')) {
            emit(
              state.copyWith(
                previewId: value['previewId'] as String?,
                clearPreview: value['previewId'] == null,
              ),
            );
          }
          if (value['sleep'] is Map) {
            emit(
              state.copyWith(
                sleep: Map.unmodifiable(
                  Map<String, dynamic>.from(value['sleep'] as Map),
                ),
              ),
            );
          }
          if (value['sessionError'] is String) {
            emit(state.copyWith(error: value['sessionError'] as String));
          }
        }
        if (value is Map && value['volume'] is num) {
          final volume = (value['volume'] as num).toDouble();
          if (!volume.isFinite) return;
          _confirmedVolume = volume.clamp(0.0, 1.0);
          if (!isClosed && !_settingVolume) {
            emit(state.copyWith(volume: _confirmedVolume));
          }
        }
      }),
    );
    _subscriptions.add(
      _handler.mediaItem.listen((item) {
        if (isClosed) return;
        if (item == null) {
          emit(
            state.copyWith(
              clearItem: true,
              playing: false,
              loading: false,
              position: Duration.zero,
              duration: Duration.zero,
            ),
          );
          return;
        }
        emit(
          state.copyWith(
            item: item,
            duration: item.duration ?? Duration.zero,
            position: item.id != state.item?.id
                ? Duration.zero
                : state.position,
          ),
        );
      }),
    );
    _subscriptions.add(
      _handler.playbackState.listen((playback) {
        if (isClosed) return;
        emit(
          state.copyWith(
            playing: playback.playing,
            speed: playback.speed,
            position: playback.playing
                ? state.position
                : playback.updatePosition,
            loading:
                playback.processingState == AudioProcessingState.loading ||
                playback.processingState == AudioProcessingState.buffering,
            shuffle: playback.shuffleMode != AudioServiceShuffleMode.none,
            repeat: playback.repeatMode,
            error: playback.errorMessage,
            clearError: playback.processingState != AudioProcessingState.error,
          ),
        );
      }),
    );
    _subscriptions.add(
      (positionStream ?? AudioService.position).listen((position) {
        if (!isClosed) emit(state.copyWith(position: position));
      }),
    );
  }

  final AudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  double _confirmedVolume = 1;
  double _lastAudibleVolume = 1;
  double? _pendingVolume;
  bool _settingVolume = false;

  // Serialize rapid slider updates; only the latest pending value is applied.
  Future<void> setVolume(double value) async {
    if (!value.isFinite || isClosed) return;
    final target = value.clamp(0.0, 1.0);
    if (target > 0) _lastAudibleVolume = target;
    _pendingVolume = target;
    emit(state.copyWith(volume: target, clearError: true));
    if (_settingVolume) return;
    _settingVolume = true;
    try {
      while (_pendingVolume != null && !isClosed) {
        final next = _pendingVolume!;
        _pendingVolume = null;
        await _handler.customAction('setVolume', {'volume': next});
        _confirmedVolume = next;
      }
    } catch (_) {
      _pendingVolume = null;
      if (!isClosed) {
        emit(
          state.copyWith(
            volume: _confirmedVolume,
            error: 'Volume gagal diubah. Coba lagi.',
          ),
        );
      }
    } finally {
      _settingVolume = false;
    }
  }

  Future<void> adjustVolume(double delta) => setVolume(state.volume + delta);
  Future<void> toggleMute() =>
      setVolume(state.volume > 0 ? 0 : _lastAudibleVolume);
  Future<void> _run(Future<void> Function() action) async {
    try {
      emit(state.copyWith(clearError: true));
      await action();
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            loading: false,
            error:
                _handler.playbackState.value.errorMessage ??
                'Pemutaran gagal. Periksa file, format audio atau koneksi dan coba lagi.',
          ),
        );
      }
    }
  }

  Future<void> playTrack(int index) => _run(() async {
    await _handler.skipToQueueItem(index);
    await _handler.play();
  });
  Future<void> setSleepTimer(String mode, {int? minutes}) => _run(() async {
    await _handler.customAction('sleepTimer', {
      'mode': mode,
      'minutes': ?minutes,
    });
  });
  Future<void> speed(double value) => _run(() async {
    await _handler.customAction('speed', {'value': value});
  });
  Future<void> preview(String id) => _run(() async {
    await _handler.customAction('preview', {'id': id});
  });
  Future<void> cancelPreview() => _run(() async {
    await _handler.customAction('cancelPreview');
  });
  Future<void> undoQueue() => _run(() async {
    await _handler.customAction('undoQueue');
  });
  Future<void> enqueueMany(List<String> ids, {bool next = false}) =>
      _run(() async {
        await _handler.customAction(next ? 'playNext' : 'enqueueMany', {
          'ids': ids,
        });
      });
  Future<void> restoreQueue(
    List<String> ids, {
    String? currentId,
    int positionMs = 0,
  }) => _run(() async {
    await _handler.customAction('loadQueue', {
      'ids': ids,
      'currentId': currentId,
      'positionMs': positionMs,
    });
  });
  Future<void> playId(String id) => _run(() async {
    await _handler.customAction('playId', {'id': id});
  });
  Future<void> openNetwork(
    List<Map<String, dynamic>> entries, {
    bool private = false,
  }) => _handler.customAction('openNetwork', {
    'entries': entries,
    'private': private,
  });
  Future<void> returnLocal() => _run(() async {
    await _handler.customAction('returnLocal');
  });
  Future<void> suspendSource() async {
    await _handler.customAction('suspendSource');
  }

  Future<void> playCollection(List<String> ids) => _run(() async {
    await _handler.customAction('playCollection', {'ids': ids});
  });
  Future<void> enqueue(String id) => _run(() async {
    await _handler.customAction('enqueue', {'id': id});
  });
  Future<void> moveQueue(int from, int to) => _run(() async {
    await _handler.customAction('moveQueue', {'from': from, 'to': to});
  });
  Future<void> removeQueue(MediaItem item) =>
      _run(() => _handler.removeQueueItem(item));
  Future<void> togglePlay() =>
      _run(() => state.playing ? _handler.pause() : _handler.play());
  Future<void> seek(Duration position) => _run(() => _handler.seek(position));
  Future<void> next() => _run(_handler.skipToNext);
  Future<void> previous() => _run(_handler.skipToPrevious);
  Future<void> toggleShuffle() => _run(
    () => _handler.setShuffleMode(
      state.shuffle
          ? AudioServiceShuffleMode.none
          : AudioServiceShuffleMode.all,
    ),
  );
  Future<void> cycleRepeat() => _run(
    () => _handler.setRepeatMode(switch (state.repeat) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    }),
  );

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    // Service tetap hidup ketika UI tidak terlihat.
    return super.close();
  }
}
