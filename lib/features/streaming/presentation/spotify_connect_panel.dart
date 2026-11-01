import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotifyConnectPanel extends StatefulWidget {
  const SpotifyConnectPanel({super.key});

  @override
  State<SpotifyConnectPanel> createState() => _SpotifyConnectPanelState();
}

class _SpotifyConnectPanelState extends State<SpotifyConnectPanel> {
  static const _channel = MethodChannel('com.swiftmusic/spotify_connect');
  Timer? _poll;
  String _status = 'Belum aktif';
  String? _error;
  bool _busy = false;

  bool get _receiverActive =>
      _status.startsWith('Menyiapkan') ||
      _status.startsWith('Siap') ||
      _status.startsWith('Terhubung');

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final status = await _channel.invokeMethod<String>('status');
      if (mounted && status != null) setState(() => _status = status);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Spotify Connect tidak tersedia.');
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Spotify Connect tersedia pada aplikasi Android saja.');
    }
  }

  Future<void> _start() async {
    setState(() { _busy = true; _error = null; });
    try {
      final started = await _channel.invokeMethod<bool>('start');
      if (started != true) throw PlatformException(code: 'start_failed');
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Spotify Connect gagal dijalankan.');
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'Build Android dengan modul Spotify Connect terbaru.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _channel.invokeMethod<void>('stop');
      await _refresh();
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? 'Spotify Connect gagal dihentikan.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Spotify Connect', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(_error ?? _status),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy || _receiverActive ? null : _start,
            icon: _busy && !_receiverActive
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speaker),
            label: const Text('Aktifkan speaker Swift Music'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Hentikan Spotify Connect',
            onPressed: _busy || !_receiverActive ? null : _stop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Setelah aktif, buka Spotify di ponsel atau perangkat lain, pilih ikon perangkat, lalu pilih “Swift Music”. Memerlukan Spotify Premium dan jaringan Wi-Fi yang sama.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    ),
  );
}
