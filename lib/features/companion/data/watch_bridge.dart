import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

/// Small state snapshots only: audio and local file paths never leave the phone.
class WatchBridge {
  WatchBridge(this.handler, {MethodChannel? channel})
    : channel = channel ?? const MethodChannel('com.swiftmusic/watch');
  final AudioHandler handler;
  final MethodChannel channel;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _pending;
  bool _closed = false;
  double _volume = 1;

  void start() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'command') throw MissingPluginException();
      final args = call.arguments;
      if (args is! Map) throw ArgumentError('Invalid watch command');
      await command(args);
      return snapshot();
    });
    _subscriptions.add(handler.mediaItem.listen((_) => _schedule()));
    _subscriptions.add(handler.playbackState.listen((_) => _schedule()));
    _subscriptions.add(
      handler.customState.listen((state) {
        if (state is Map && state['volume'] is num) {
          _volume = (state['volume'] as num).toDouble();
          _schedule();
        }
      }),
    );
    _schedule();
  }

  Map<String, Object> snapshot() {
    final item = handler.mediaItem.value;
    final state = handler.playbackState.value;
    return {
      'version': 1,
      'title': item?.title ?? 'Swift Music',
      'artist': item?.artist ?? '',
      'playing': state.playing,
      'positionMs': state.position.inMilliseconds,
      'durationMs': item?.duration?.inMilliseconds ?? 0,
      'volume': _volume,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> command(Map<dynamic, dynamic> args) async {
    switch (args['action']) {
      case 'state':
        break;
      case 'play':
        await handler.play();
      case 'pause':
        await handler.pause();
      case 'next':
        await handler.skipToNext();
      case 'previous':
        await handler.skipToPrevious();
      case 'volume':
        final value = args['value'];
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw ArgumentError('Invalid volume');
        }
        await handler.customAction('setVolume', {'volume': value.toDouble()});
      case 'seek':
        final value = args['value'];
        final duration = handler.mediaItem.value?.duration?.inMilliseconds ?? 0;
        if (value is! num || !value.isFinite || value < 0 || value > duration) {
          throw ArgumentError('Invalid position');
        }
        await handler.seek(Duration(milliseconds: value.round()));
      default:
        throw ArgumentError('Unsupported watch command');
    }
  }

  void _schedule() {
    if (_closed || _pending != null) return;
    _pending = Timer(const Duration(milliseconds: 500), () async {
      _pending = null;
      try {
        await channel.invokeMethod<void>('publish', snapshot());
      } on MissingPluginException {
        // Desktop tests and platforms without a companion bridge.
      } on PlatformException {
        // A disconnected watch must never interrupt playback.
      }
    });
  }

  Future<void> close() async {
    _closed = true;
    _pending?.cancel();
    channel.setMethodCallHandler(null);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
