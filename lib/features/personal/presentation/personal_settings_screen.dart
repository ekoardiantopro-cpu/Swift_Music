import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import 'personal_cubit.dart';

class PersonalSettingsScreen extends StatefulWidget {
  const PersonalSettingsScreen({super.key});
  @override
  State<PersonalSettingsScreen> createState() => _PersonalSettingsScreenState();
}

class _PersonalSettingsScreenState extends State<PersonalSettingsScreen> {
  String? _message;
  bool _busy = false;
  Future<void> _work(Future<String> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await work();
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Proses belum berhasil. Coba kembali.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = PersonalScope.maybeOf(context)!;
    final personal = scope.controller;
    final state = scope.state;
    final player = context.watch<PlayerCubit>();
    final tracks = context.watch<CatalogCubit>().state.tracks;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Swift Music')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            title: const Text('Gesture player'),
            subtitle: const Text(
              'Geser untuk next/previous, ketuk dua kali untuk favorit',
            ),
            value: state.settings['gestures'] != false,
            onChanged: (v) => personal.setting('gestures', v),
          ),
          SwitchListTile(
            title: const Text('Layar tetap menyala saat membaca lirik'),
            value: state.flag('keepLyricsAwake'),
            onChanged: (v) => personal.setting('keepLyricsAwake', v),
          ),
          const Text(
            'Tampilan',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          DropdownButtonFormField<String>(
            initialValue: state.text('motion', 'full'),
            decoration: const InputDecoration(labelText: 'Animasi'),
            items: const [
              DropdownMenuItem(value: 'full', child: Text('Penuh')),
              DropdownMenuItem(
                value: 'reduced',
                child: Text('Ringan — visualizer statis'),
              ),
              DropdownMenuItem(value: 'off', child: Text('Nonaktif')),
            ],
            onChanged: (v) => personal.setting('motion', v),
          ),
          const SizedBox(height: 16),
          const Text('Warna aksen'),
          Wrap(
            children: [
              for (final color in const [
                Color(0xFF1DB954),
                Color(0xFFB488FF),
                Color(0xFFFF6BA9),
                Color(0xFF52C7F2),
                Color(0xFFFFBE63),
                Color(0xFFFFFFFF),
              ])
                IconButton(
                  tooltip: 'Aksen ${color.toARGB32().toRadixString(16)}',
                  onPressed: () => personal.setting('accent', color.toARGB32()),
                  icon: Icon(Icons.circle, color: color, size: 32),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: state.text('playerBackground', 'purple'),
            decoration: const InputDecoration(labelText: 'Latar player'),
            items: const [
              DropdownMenuItem(value: 'purple', child: Text('Ungu')),
              DropdownMenuItem(value: 'black', child: Text('Hitam')),
              DropdownMenuItem(value: 'blue', child: Text('Biru')),
              DropdownMenuItem(value: 'warm', child: Text('Hangat')),
            ],
            onChanged: (v) => personal.setting('playerBackground', v),
          ),
          const SizedBox(height: 24),
          const Text(
            'Audio',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(
            'Batas volume aplikasi: ${(state.value('maxVolume', 1) * 100).round()}%',
          ),
          Slider(
            value: state.value('maxVolume', 1).clamp(.1, 1),
            min: .1,
            max: 1,
            divisions: 18,
            onChanged: (v) => personal.setting('maxVolume', v),
          ),
          SwitchListTile(
            title: const Text('Jeda saat volume aplikasi nol'),
            value: state.flag('pauseOnMute'),
            onChanged: (v) => personal.setting('pauseOnMute', v),
          ),
          DropdownButtonFormField<double>(
            key: ValueKey(player.state.speed),
            initialValue: player.state.speed,
            decoration: const InputDecoration(labelText: 'Kecepatan pemutaran'),
            items: [
              for (final value in ({
                .5,
                .75,
                1.0,
                1.25,
                1.5,
                2.0,
                player.state.speed,
              }.toList()..sort()))
                DropdownMenuItem(value: value, child: Text('$value×')),
            ],
            onChanged: (v) {
              if (v != null) player.speed(v);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Data dan diagnostik',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Hitung ruang musik'),
            onTap: _busy
                ? null
                : () => _work(() async {
                    var audio = 0, covers = 0;
                    final seen = <String>{};
                    for (final track in tracks) {
                      for (final entry in [
                        (track.audioUrl, false),
                        (track.artUrl, true),
                      ]) {
                        final uri = Uri.tryParse(entry.$1);
                        if (uri?.scheme != 'file' || !seen.add(entry.$1)) {
                          continue;
                        }
                        try {
                          final bytes = await File.fromUri(uri!).length();
                          if (entry.$2) {
                            covers += bytes;
                          } else {
                            audio += bytes;
                          }
                        } catch (_) {}
                      }
                    }
                    return 'Musik: ${(audio / 1048576).toStringAsFixed(1)} MiB • cover: ${(covers / 1048576).toStringAsFixed(1)} MiB';
                  }),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Bersihkan cache gambar'),
            subtitle: const Text('Musik dan cover lokal tetap disimpan'),
            onTap: _busy
                ? null
                : () => _work(() async {
                    for (final url
                        in tracks
                            .map((t) => t.artUrl)
                            .where((u) => u.startsWith('https://'))
                            .toSet()) {
                      await CachedNetworkImage.evictFromCache(url);
                    }
                    PaintingBinding.instance.imageCache.clear();
                    PaintingBinding.instance.imageCache.clearLiveImages();
                    return 'Cache gambar koleksi aktif telah dibersihkan.';
                  }),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Ekspor diagnostik'),
            subtitle: const Text(
              'Versi, platform dan kegagalan; tanpa path file atau judul lagu',
            ),
            onTap: _busy
                ? null
                : () => _work(() async {
                    final package = await PackageInfo.fromPlatform();
                    final document = {
                      'app': 'Swift Music',
                      'version': package.version,
                      'build': package.buildNumber,
                      'os': Platform.operatingSystem,
                      'osVersion': Platform.operatingSystemVersion,
                      'date': DateTime.now().toIso8601String(),
                      'tracks': tracks.length,
                      'missing': tracks.where((t) => t.missing).length,
                      'problems': scope.state.songs.values
                          .map((v) => v.text('problem'))
                          .where((v) => v.isNotEmpty)
                          .toList(),
                      'playing': player.state.playing,
                    };
                    final result = await FilePicker.saveFile(
                      fileName: 'swift-music-diagnostics.json',
                      bytes: Uint8List.fromList(
                        utf8.encode(jsonEncode(document)),
                      ),
                      mimeType: 'application/json',
                    );
                    return result == null
                        ? 'Ekspor dibatalkan.'
                        : 'Diagnostik berhasil disimpan.';
                  }),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_message!)),
        ],
      ),
    );
  }
}
