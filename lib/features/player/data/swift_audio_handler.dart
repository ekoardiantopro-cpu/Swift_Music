import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../catalog/domain/track.dart';
import '../domain/sleep_timer.dart';
import 'playback_session_repository.dart';

/// Satu-satunya pemilik AudioPlayer. UI dan kontrol OS memakai handler ini.
class SwiftAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<MediaItem> _items = [];
  final Map<String, MediaItem> _catalog = {};
  Future<void> _queueTail = Future.value();
  bool _mutating = false;
  bool _loaded = false;
  bool _failed = false;
  Future<void>? _preparing;
  final PlaybackSessionRepository _sessions;
  late final SleepTimer _sleep;
  Timer? _checkpoint;
  Future<void> _sessionWrites = Future.value();
  bool _sessionReady = false;
  Duration _resumePosition = Duration.zero;
  LoopMode? _guardedRepeat;
  String? _sessionError;
  int _sleepGeneration = 0;
  double _maxVolume = 1;
  bool _pauseOnMute = false;
  AudioPlayer? _previewPlayer;
  Timer? _previewTimer;
  bool _previewResume = false;
  int _previewRevision = 0;
  String? _previewId;
  final List<Map<String, dynamic>> _queueUndo = [];
  Future<void> Function(List<String>, String?, Duration)? onQueueHistory;
  Map<String, dynamic>? _networkReturn;
  bool get _networkActive => _networkReturn != null;

  Future<void> _leaveNetwork() async {
    final snapshot = _networkReturn;
    if (snapshot == null) return;
    await customAction('loadQueue', {...snapshot, '_undo': true});
    _networkReturn = null;
    await _player.setShuffleModeEnabled(snapshot['shuffle'] == true);
    await _player.setLoopMode(snapshot['repeat'] as LoopMode);
    await _saveSession();
  }

  AudioSource _source(MediaItem item) {
    final uri = Uri.parse(item.extras!['url'] as String);
    return switch (item.extras?['kind']) {
      'hls' => HlsAudioSource(uri, tag: item),
      'dash' => DashAudioSource(uri, tag: item),
      _ => AudioSource.uri(uri, tag: item),
    };
  }

  Future<void> applyPreferences(Map<String, dynamic> preferences) async {
    final settings = preferences['settings'] as Map? ?? {};
    _maxVolume =
        (settings['maxVolume'] is num
                ? (settings['maxVolume'] as num).toDouble()
                : 1.0)
            .clamp(.1, 1);
    _pauseOnMute = settings['pauseOnMute'] == true;
    if (_player.volume > _maxVolume) await _player.setVolume(_maxVolume);
    if (_pauseOnMute && _player.volume == 0) await pause();
  }

  Future<void> _endPreview({bool resume = false}) async {
    _previewRevision++;
    _previewTimer?.cancel();
    final preview = _previewPlayer;
    final shouldResume = _previewResume && resume;
    _previewPlayer = null;
    _previewId = null;
    _previewResume = false;
    if (preview != null) await preview.dispose();
    _publishCustom();
    if (shouldResume) await play();
  }

  Future<void> _preview(String id) async {
    final item = _catalog[id];
    if (item == null) throw ArgumentError('Lagu tidak ditemukan.');
    final resume = _previewPlayer == null ? _player.playing : _previewResume;
    await _endPreview();
    await _player.pause();
    final revision = _previewRevision;
    final preview = AudioPlayer(handleInterruptions: false);
    _previewPlayer = preview;
    _previewResume = resume;
    _previewId = id;
    _publishCustom();
    try {
      await preview.setVolume(_player.volume);
      await preview.setUrl(item.extras!['url'] as String);
      if (revision != _previewRevision) return;
      if ((preview.duration ?? Duration.zero) > const Duration(seconds: 45)) {
        await preview.seek(const Duration(seconds: 30));
      }
      _previewTimer = Timer(const Duration(seconds: 15), () {
        unawaited(_endPreview(resume: true));
      });
      unawaited(
        preview
            .play()
            .then((_) {
              if (revision == _previewRevision &&
                  preview.processingState == ProcessingState.completed) {
                unawaited(_endPreview(resume: true));
              }
            })
            .catchError((Object error) {
              if (revision == _previewRevision) {
                unawaited(_endPreview(resume: true));
              }
            }),
      );
    } catch (_) {
      if (revision == _previewRevision) {
        await _endPreview(resume: true);
        rethrow;
      }
    }
  }

  void _publishCustom() => customState.add({
    'canUndoQueue': _queueUndo.isNotEmpty,
    'previewId': _previewId,
    'volume': _player.volume,
    'sleep': _sleep.json,
    'sessionError': _sessionError,
  });
  Future<void> _finishSleep() async {
    _sleepGeneration++;
    try {
      await _queueTail;
      await _preparing;
      await _player.pause();
      await _releaseEndGuard();
      await _saveSession();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _releaseEndGuard() async {
    final repeat = _guardedRepeat;
    _guardedRepeat = null;
    if (repeat != null) await _player.setLoopMode(repeat);
    _broadcast();
  }

  Future<void> restoreSession() async {
    try {
      final stored = await _sessions.load();
      if (stored != null) {
        final session = stored.reconcile(_catalog.keys.toSet());
        _items = session.ids.map((id) => _catalog[id]!).toList();
        queue.add(List.unmodifiable(_items));
        final selected = _catalog[session.currentId];
        mediaItem.add(selected);
        _resumePosition = Duration(milliseconds: session.positionMs);
        if (selected?.duration != null &&
            _resumePosition > selected!.duration!) {
          _resumePosition = selected.duration!;
        }
        await _player.setVolume(session.volume);
        await _player.setSpeed(session.speed);
        await _player.setLoopMode(switch (session.repeat) {
          'one' => LoopMode.one,
          'all' => LoopMode.all,
          _ => LoopMode.off,
        });
        await _player.setShuffleModeEnabled(session.shuffle);
      }
    } catch (_) {
      _sessionError =
          'Sesi terakhir tidak dapat dipulihkan. Koleksi musik tetap tersedia.';
    }
    _sessionReady = true;
    _publishCustom();
    _broadcast();
  }

  Future<void> _saveSession() async {
    if (!_sessionReady || _mutating || _networkActive) return;
    final session = PlaybackSession(
      ids: _items.map((item) => item.id),
      currentId: mediaItem.value?.id,
      positionMs: (_loaded ? _player.position : _resumePosition).inMilliseconds,
      volume: _player.volume,
      speed: _player.speed,
      shuffle: _player.shuffleModeEnabled,
      repeat: switch (_guardedRepeat ?? _player.loopMode) {
        LoopMode.one => 'one',
        LoopMode.all => 'all',
        _ => 'none',
      },
    );
    _sessionWrites = _sessionWrites
        .catchError((_) {})
        .then((_) => _sessions.save(session));
    try {
      await _sessionWrites;
      if (_sessionError != null) {
        _sessionError = null;
        _publishCustom();
      }
    } catch (_) {
      _sessionError =
          'Sesi terakhir belum tersimpan. Coba jeda pemutaran kembali.';
      _publishCustom();
    }
  }

  SwiftAudioHandler({PlaybackSessionRepository? sessions})
    : _sessions = sessions ?? LocalPlaybackSessionRepository() {
    _sleep = SleepTimer(onExpire: _finishSleep, onChanged: _publishCustom);
    _subscriptions.add(
      _player.positionDiscontinuityStream.listen((event) {
        if (event.reason == PositionDiscontinuityReason.autoAdvance) {
          // Loop-one guard prevents the next song starting before the service pauses.
          unawaited(
            _sleep.trackBoundary(
              loaded: _loaded,
              playing: _player.playing,
              previouslyReady:
                  event.previousEvent.processingState == ProcessingState.ready,
              sameItem:
                  event.previousEvent.currentIndex == event.event.currentIndex,
            ),
          );
        }
      }),
    );
    _subscriptions.add(
      _player.volumeStream.listen((volume) {
        _publishCustom();
      }),
    );
    _subscriptions.add(_player.errorStream.listen(_reportError));
    _subscriptions.add(_player.playbackEventStream.listen((_) => _broadcast()));
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        // A stopped network source can still emit indices while restoring shuffle.
        if (_mutating || !_loaded) return;
        if (index != null && index < _items.length) {
          mediaItem.add(_items[index]);
          unawaited(_saveSession());
        }
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (_mutating || !_loaded) return;
        final index = _player.currentIndex;
        if (duration == null || index == null || index >= _items.length) return;
        _items[index] = _items[index].copyWith(duration: duration);
        queue.add(List.unmodifiable(_items));
        mediaItem.add(_items[index]);
      }),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (state.playing && _checkpoint == null) {
          _checkpoint = Timer.periodic(
            const Duration(seconds: 5),
            (_) => unawaited(_saveSession()),
          );
        } else if (!state.playing) {
          _checkpoint?.cancel();
          _checkpoint = null;
        }
        // Completed tetap tersedia untuk replay; UI tidak menampilkan pause palsu.
        if (state.processingState == ProcessingState.completed) {
          unawaited(_player.pause());
        }
        _broadcast();
      }),
    );
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'suspendSource') {
      await _endPreview();
      await _queueTail;
      if (_loaded) _resumePosition = _player.position;
      await _player.pause();
      _loaded = false;
      // stop releases the native decoder/buffers; keep a lazy local session.
      await _player.stop();
      await _saveSession();
      _broadcast();
      return null;
    }
    if (name == 'returnLocal') {
      await _leaveNetwork();
      return null;
    }
    if (name == 'openNetwork') {
      final entries = (extras?['entries'] as List? ?? [])
          .whereType<Map>()
          .toList();
      if (entries.isEmpty || entries.length > 1000) {
        throw ArgumentError('Playlist stream kosong atau terlalu besar.');
      }
      final items = <MediaItem>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final uri = Uri.tryParse(entry['url'] as String? ?? '');
        if (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw ArgumentError('Pemutar internal memerlukan HTTP/HTTPS.');
        }
        items.add(
          MediaItem(
            id: 'network-$i',
            title: extras?['private'] == true
                ? 'Private Playback'
                : entry['title'] as String? ?? 'Network Stream',
            artist: extras?['private'] == true ? 'Swift Music' : uri.host,
            extras: {
              'url': uri.toString(),
              'kind': entry['kind'] ?? 'auto',
              'network': true,
              'lyrics': entry['lyrics'],
              'private': extras?['private'] == true,
            },
          ),
        );
      }
      await _endPreview();
      await _saveSession();
      _networkReturn ??= {
        'ids': _items.map((e) => e.id).toList(),
        'currentId': mediaItem.value?.id,
        'positionMs':
            (_loaded ? _player.position : _resumePosition).inMilliseconds,
        'shuffle': _player.shuffleModeEnabled,
        'repeat': _guardedRepeat ?? _player.loopMode,
      };
      await _editQueue(() async {
        _sleep.cancel();
        await _releaseEndGuard();
        await _player.pause();
        await _player.stop();
        await _player.setShuffleModeEnabled(false);
        await _player.setLoopMode(LoopMode.off);
        _loaded = false;
        _failed = false;
        _resumePosition = Duration.zero;
        _items = items;
        await _prepare(0);
      }, remember: false);
      await play();
      return null;
    }
    if (_networkActive &&
        {
          'playId',
          'playCollection',
          'enqueue',
          'enqueueMany',
          'playNext',
          'preview',
        }.contains(name)) {
      await _leaveNetwork();
    }
    if (_networkActive && name == 'loadQueue' && extras?['_undo'] != true) {
      await _leaveNetwork();
    }
    if (name == 'setVolume') {
      final value = extras?['volume'];
      if (value is! num || !value.isFinite) {
        throw ArgumentError('Volume harus berupa angka finite.');
      }
      await _player.setVolume(value.toDouble().clamp(0.0, _maxVolume));
      await _previewPlayer?.setVolume(_player.volume);
      if (_pauseOnMute && _player.volume == 0) await pause();
      await _saveSession();
      return null;
    }
    if (name == 'speed') {
      final value = extras?['value'];
      if (value is! num || !value.isFinite || value < .5 || value > 2) {
        throw ArgumentError('Kecepatan harus 0,5–2×.');
      }
      await _player.setSpeed(value.toDouble());
      await _saveSession();
      _broadcast();
      return null;
    }
    if (name == 'preview') {
      await _preview(extras!['id'] as String);
      return null;
    }
    if (name == 'cancelPreview') {
      await _endPreview(resume: true);
      return null;
    }
    if (name == 'undoQueue') {
      if (_queueUndo.isNotEmpty) {
        final snapshot = _queueUndo.removeLast();
        await customAction('loadQueue', {...snapshot, '_undo': true});
      }
      return null;
    }
    if (name == 'enqueueMany' || name == 'playNext') {
      final ids = (extras?['ids'] as List? ?? []).whereType<String>().toSet();
      await _editQueue(() async {
        final current = mediaItem.value?.id;
        var offset = 1;
        for (final id in ids) {
          final item = _catalog[id];
          if (item == null || (name == 'playNext' && id == current)) continue;
          final old = _items.indexWhere((entry) => entry.id == id);
          if (name == 'enqueueMany') {
            if (old >= 0) continue;
            _items.add(item);
            if (_loaded) {
              await _player.addAudioSource(
                AudioSource.uri(
                  Uri.parse(item.extras!['url'] as String),
                  tag: item,
                ),
              );
            }
          } else {
            if (old >= 0) _items.removeAt(old);
            final selected = _items.indexWhere((entry) => entry.id == current);
            final target = (selected + offset).clamp(0, _items.length);
            _items.insert(target, item);
            if (_loaded) {
              if (old >= 0) {
                await _player.moveAudioSource(old, target);
              } else {
                await _player.insertAudioSource(
                  target,
                  AudioSource.uri(
                    Uri.parse(item.extras!['url'] as String),
                    tag: item,
                  ),
                );
              }
            }
            offset++;
          }
        }
      });
      return null;
    }
    if (name == 'loadQueue') {
      await _endPreview();
      final ids = (extras?['ids'] as List? ?? []).whereType<String>().toSet();
      final selected = extras?['currentId'] as String?;
      final position =
          (extras?['positionMs'] is num
                  ? (extras!['positionMs'] as num).toInt()
                  : 0)
              .clamp(0, 86400000);
      await _editQueue(() async {
        _sleep.cancel();
        await _releaseEndGuard();
        await _player.pause();
        await _player.stop();
        _loaded = false;
        _failed = false;
        _items = ids.map((id) => _catalog[id]).whereType<MediaItem>().toList();
      }, remember: extras?['_undo'] != true);
      final current =
          _items.where((item) => item.id == selected).firstOrNull ??
          _items.firstOrNull;
      _resumePosition = current?.id == selected
          ? Duration(milliseconds: position)
          : Duration.zero;
      mediaItem.add(current);
      _broadcast();
      await _saveSession();
      if (extras?['_undo'] == true && extras?['playing'] == true) await play();
      return null;
    }
    if (name == 'sleepTimer') {
      final mode = extras?['mode'];
      if (mode == 'cancel') {
        _sleep.cancel();
        await _releaseEndGuard();
      } else if (mode == 'duration') {
        final minutes = extras?['minutes'];
        if (minutes is! int || ![15, 30, 60].contains(minutes)) {
          throw ArgumentError('Pilih 15, 30 atau 60 menit.');
        }
        _sleep.cancel();
        await _releaseEndGuard();
        _sleep.start(Duration(minutes: minutes));
      } else if (mode == 'track') {
        if (mediaItem.value == null) {
          throw StateError('Pilih lagu terlebih dahulu.');
        }
        _guardedRepeat ??= _player.loopMode;
        await _player.setLoopMode(LoopMode.one);
        _sleep.afterTrack(mediaItem.value!.id);
      } else {
        throw ArgumentError('Mode timer tidak valid.');
      }
      _publishCustom();
      _broadcast();
      return null;
    }
    if (name == 'playId' || name == 'enqueue') {
      final sleepGeneration = _sleepGeneration;
      final item = _catalog[extras?['id']];
      if (item == null) throw ArgumentError('Lagu tidak ada di katalog.');
      if (!_items.any((entry) => entry.id == item.id)) await addQueueItem(item);
      if (name == 'playId') {
        await skipToQueueItem(
          _items.indexWhere((entry) => entry.id == item.id),
        );
        if (sleepGeneration == _sleepGeneration) await play();
      }
      return null;
    }
    if (name == 'playCollection') {
      final sleepGeneration = _sleepGeneration;
      final ids = (extras?['ids'] as List? ?? []).cast<String>().toSet();
      final items = ids
          .map((id) => _catalog[id])
          .whereType<MediaItem>()
          .toList();
      if (items.isEmpty) return null;
      await _editQueue(() async {
        if (_sleep.trackId != null) {
          _sleep.cancel();
          await _releaseEndGuard();
        }
        await _player.pause();
        _items = items;
        queue.add(List.unmodifiable(_items));
        _loaded = false;
        _resumePosition = Duration.zero;
        await _prepare(0);
        if (sleepGeneration == _sleepGeneration) {
          unawaited(
            _player.play().catchError((Object error) {
              _reportError(error);
            }),
          );
        }
      });
      return null;
    }
    if (name == 'moveQueue') {
      await moveQueueItem(extras!['from'] as int, extras['to'] as int);
      return null;
    }
    return super.customAction(name, extras);
  }

  void configureCatalog(List<Track> tracks) {
    if (_loaded) throw StateError('Katalog sudah dimuat.');
    _items = tracks
        .map(
          (t) => MediaItem(
            id: t.id,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration: t.duration,
            artUri: t.artUrl.isEmpty ? null : Uri.parse(t.artUrl),
            extras: {'url': t.audioUrl},
          ),
        )
        .toList();
    _catalog.clear();
    _catalog.addEntries(_items.map((item) => MapEntry(item.id, item)));
    queue.add(List.unmodifiable(_items));
    if (_items.isNotEmpty) mediaItem.add(_items.first);
  }

  Future<void> refreshMetadata(List<Track> tracks) async {
    final durations = {for (final item in _items) item.id: item.duration};
    for (final track in tracks) {
      _catalog[track.id] = MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration:
            track.duration ??
            durations[track.id] ??
            _catalog[track.id]?.duration,
        artUri: track.artUrl.isEmpty ? null : Uri.parse(track.artUrl),
        extras: {'url': track.audioUrl},
      );
    }
    final selected = mediaItem.value?.id;
    _items = _items.map((item) => _catalog[item.id] ?? item).toList();
    queue.add(List.unmodifiable(_items));
    if (selected != null && _catalog[selected] != null) {
      mediaItem.add(_catalog[selected]);
    }
  }

  Future<void> _load(int index) async {
    final pending = _preparing;
    if (pending != null) {
      await pending;
      return;
    }
    final operation = _prepare(index);
    _preparing = operation;
    try {
      await operation;
    } finally {
      _preparing = null;
    }
  }

  /// Tambahkan lagu tanpa mengganti source/posisi lagu yang sedang diputar.
  Future<void> appendTracks(List<Track> tracks) => _editQueue(() async {
    await _preparing;
    final additions = tracks
        .where((track) => !_items.any((item) => item.id == track.id))
        .map(
          (track) => MediaItem(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            artUri: track.artUrl.isEmpty ? null : Uri.parse(track.artUrl),
            extras: {'url': track.audioUrl},
          ),
        )
        .toList();
    if (additions.isEmpty) return;
    _catalog.addEntries(additions.map((item) => MapEntry(item.id, item)));
    if (_networkActive) return;
    _items.addAll(additions);
    queue.add(List.unmodifiable(_items));
    if (_loaded) {
      try {
        await _player.addAudioSources(
          additions
              .map(
                (item) => AudioSource.uri(
                  Uri.parse(item.extras!['url'] as String),
                  tag: item,
                ),
              )
              .toList(),
        );
      } catch (error) {
        _reportError(error);
      }
    }
  });

  Future<void> _editQueue(
    Future<void> Function() operation, {
    bool remember = true,
  }) {
    final completion = Completer<void>();
    _queueTail = _queueTail.catchError((_) {}).then((_) async {
      final selectedId = mediaItem.value?.id;
      try {
        await _preparing;
        if (remember && _sessionReady && _items.isNotEmpty && !_networkActive) {
          final ids = _items.map((item) => item.id).toList();
          final position = _loaded ? _player.position : _resumePosition;
          _queueUndo.add({
            'ids': ids,
            'currentId': selectedId,
            'positionMs': position.inMilliseconds,
            'playing': _player.playing,
          });
          if (_queueUndo.length > 20) _queueUndo.removeAt(0);
          await onQueueHistory?.call(ids, selectedId, position);
        }
        _mutating = true;
        await operation();
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _mutating = false;
        final selected = _loaded
            ? (_player.currentIndex ?? 0)
            : _items.indexWhere((item) => item.id == selectedId);
        final index = _items.isEmpty ? 0 : selected.clamp(0, _items.length - 1);
        if (_items.isEmpty || (!_loaded && _items[index].id != selectedId)) {
          _resumePosition = Duration.zero;
        }
        if (_loaded && _items.isNotEmpty && _player.duration != null) {
          _items[index] = _items[index].copyWith(duration: _player.duration);
        }
        queue.add(List.unmodifiable(_items));
        if (_items.isEmpty) {
          mediaItem.add(null);
        } else {
          mediaItem.add(_items[index]);
        }
        _broadcast();
        unawaited(_saveSession());
        _publishCustom();
      }
    });
    return completion.future;
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) => _editQueue(() async {
    final item = mediaItem;
    if (_items.any((entry) => entry.id == item.id)) return;
    _items.add(item);
    if (_loaded) {
      await _player.addAudioSource(
        AudioSource.uri(Uri.parse(item.extras!['url'] as String), tag: item),
      );
    }
  });

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) => _editQueue(() async {
    final item = mediaItem;
    final index = _items.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return;
    if (_sleep.trackId == item.id) {
      _sleep.cancel();
      await _releaseEndGuard();
    }
    _items.removeAt(index);
    if (_loaded) await _player.removeAudioSourceAt(index);
    if (_items.isEmpty) {
      await _player.pause();
      await stop();
      _loaded = false;
    }
  });

  Future<void> moveQueueItem(int from, int to) => _editQueue(() async {
    if (from < 0 ||
        from >= _items.length ||
        to < 0 ||
        to >= _items.length ||
        from == to) {
      return;
    }
    final item = _items.removeAt(from);
    _items.insert(to, item);
    if (_loaded) await _player.moveAudioSource(from, to);
  });

  Future<void> removeCatalogTrack(String id) async {
    final item = _catalog[id];
    if (item != null) await removeQueueItem(item);
    _catalog.remove(id);
  }

  Future<void> _prepare(int index) async {
    _failed = false;
    try {
      await _player.setAudioSources(
        _items.map((item) => _source(item)).toList(),
        initialIndex: index,
        initialPosition: _resumePosition,
      );
      _loaded = true;
      if (!_mutating && _items.isNotEmpty) {
        final selected = (_player.currentIndex ?? index).clamp(
          0,
          _items.length - 1,
        );
        _items[selected] = _items[selected].copyWith(
          duration: _player.duration,
        );
        queue.add(List.unmodifiable(_items));
        mediaItem.add(_items[selected]);
        _broadcast();
      }
    } catch (error) {
      _reportError(error);
      rethrow;
    }
  }

  void _reportError(Object error) {
    // Muat ulang playlist pada retry, termasuk kegagalan saat streaming.
    if (_loaded) _resumePosition = _player.position;
    _loaded = false;
    _failed = true;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        playing: false,
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        errorCode: 1,
        errorMessage:
            (_player.currentIndex != null &&
                _player.currentIndex! < _items.length &&
                (_items[_player.currentIndex!].extras?['url'] as String? ?? '')
                    .startsWith('file:'))
            ? 'File ini rusak atau codec audionya belum didukung perangkat. Coba file/format lain.'
            : 'Audio tidak dapat dimuat. Periksa koneksi lalu coba lagi.',
      ),
    );
  }

  void _broadcast() {
    // Idle events emitted after a decoder error must not erase its message.
    if (_failed || _mutating) return;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing,
        updatePosition: _loaded ? _player.position : _resumePosition,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _items.isEmpty
            ? null
            : _loaded
            ? _player.currentIndex
            : _items.indexWhere((item) => item.id == mediaItem.value?.id),
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (_guardedRepeat ?? _player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_previewPlayer != null) await _endPreview();
    final sleepGeneration = _sleepGeneration;
    await _queueTail;
    if (await _sleep.expireIfDue()) return;
    if (_items.isEmpty) return;
    if (!_loaded) {
      final selected = _items.indexWhere(
        (item) => item.id == mediaItem.value?.id,
      );
      await _load(selected < 0 ? 0 : selected);
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: _player.effectiveIndices.first);
    }
    if (sleepGeneration != _sleepGeneration) return;
    // play() selesai saat playback berhenti, jadi jangan await di aksi UI.
    unawaited(
      _player.play().catchError((Object error) {
        _reportError(error);
      }),
    );
  }

  @override
  Future<void> pause() async {
    if (_previewPlayer != null) await _endPreview();
    await _queueTail;
    await _player.pause();
    await _saveSession();
  }

  @override
  Future<void> seek(Duration position) async {
    await _queueTail;
    if (!_loaded) {
      final upper =
          mediaItem.value?.duration?.inMilliseconds ?? position.inMilliseconds;
      _resumePosition = Duration(
        milliseconds: position.inMilliseconds.clamp(0, upper < 0 ? 0 : upper),
      );
      _broadcast();
      await _saveSession();
      return;
    }
    final duration = _player.duration;
    final upper = duration?.inMilliseconds ?? position.inMilliseconds;
    await _player.seek(
      Duration(milliseconds: position.inMilliseconds.clamp(0, upper).toInt()),
    );
    await _saveSession();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _queueTail;
    if (index < 0 || index >= _items.length) return;
    if (_sleep.trackId != null && _sleep.trackId != _items[index].id) {
      _sleep.cancel();
      await _releaseEndGuard();
    }
    _resumePosition = Duration.zero;
    if (!_loaded) {
      await _load(index);
    }
    await _player.seek(Duration.zero, index: index);
    await _saveSession();
  }

  @override
  Future<void> skipToNext() async {
    await _queueTail;
    final selected = _items.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    final next = _loaded
        ? _player.nextIndex
        : (selected + 1 < _items.length ? selected + 1 : null);
    if (next != null) await skipToQueueItem(next);
  }

  @override
  Future<void> skipToPrevious() async {
    await _queueTail;
    if ((_loaded ? _player.position : _resumePosition) >
        const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else {
      final selected = _items.indexWhere(
        (item) => item.id == mediaItem.value?.id,
      );
      final previous = _loaded
          ? _player.previousIndex
          : (selected > 0 ? selected - 1 : null);
      if (previous != null) await skipToQueueItem(previous);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    await _saveSession();
    _broadcast();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    };
    if (_guardedRepeat != null) {
      _guardedRepeat = mode;
    } else {
      await _player.setLoopMode(mode);
    }
    await _saveSession();
    _broadcast();
  }

  @override
  Future<void> stop() async {
    if (_previewPlayer != null) await _endPreview();
    _sleep.cancel();
    await _releaseEndGuard();
    await _saveSession();
    _failed = false;
    await _player.stop();
    await super.stop();
  }

  /// Hanya untuk teardown pemilik service/test, bukan saat modal ditutup.
  Future<void> dispose() async {
    await _endPreview();
    _checkpoint?.cancel();
    _sleep.dispose();
    await _saveSession();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }
}
