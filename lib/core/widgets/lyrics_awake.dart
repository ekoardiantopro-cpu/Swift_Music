import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/personal/presentation/personal_cubit.dart';

class LyricsAwake extends StatefulWidget {
  const LyricsAwake({super.key, required this.lyrics, required this.child});
  final bool lyrics;
  final Widget child;
  @override
  State<LyricsAwake> createState() => _LyricsAwakeState();
}

class _LyricsAwakeState extends State<LyricsAwake> with WidgetsBindingObserver {
  bool _foreground = true, _enabled = false;
  static const _channel = MethodChannel('com.swiftmusic/system');
  static final _owners = <Object>{};
  static bool _sent = false;
  void _apply(bool value) {
    if (value) {
      _owners.add(this);
    } else {
      _owners.remove(this);
    }
    final desired = _owners.isNotEmpty;
    if (_sent == desired) return;
    _sent = desired;
    unawaited(_send(desired));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _send(bool value) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('keepAwake', {'enabled': value});
    } catch (_) {}
  }

  void _sync() {
    final desired =
        widget.lyrics &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (PersonalScope.maybeOf(context)?.state.flag('keepLyricsAwake') ??
            false);
    if (desired == _enabled) return;
    _enabled = desired;
    _apply(desired);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LyricsAwake oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_enabled) _apply(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
