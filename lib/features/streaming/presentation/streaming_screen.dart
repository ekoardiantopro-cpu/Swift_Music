import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../../player/presentation/widgets/mini_player.dart';
import '../data/network_resolver.dart';
import '../data/network_subtitles.dart';
import '../domain/network_playlist.dart';
import '../domain/service_link.dart';
import 'source_icons.dart';
import 'service_player.dart';
import 'video_stream_screen.dart';
import 'spotify_connect_panel.dart';

class SourceShortcuts extends StatefulWidget {
  const SourceShortcuts({super.key});
  @override
  State<SourceShortcuts> createState() => _SourceShortcutsState();
}

class _SourceShortcutsState extends State<SourceShortcuts> {
  bool _visible = false;
  int _entrance = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _entrance++;
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final source in MusicSource.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TweenAnimationBuilder<double>(
              key: ValueKey((source, _entrance)),
              tween: Tween(begin: fullMotionAllowed(context) ? 0 : 1, end: 1),
              duration: motionDuration(context, 480 + source.index * 80),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - value)),
                  child: child,
                ),
              ),
              child: PressScale(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
                    ),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StreamingScreen(initial: source),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SourceIcon(source),
                      const SizedBox(height: 8),
                      Text(
                        source.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({
    super.key,
    this.initial = MusicSource.network,
    this.tvDigital = false,
  });
  final MusicSource initial;
  final bool tvDigital;
  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  late MusicSource _source = widget.initial;
  final _input = TextEditingController();
  List<StreamEntry> _entries = [];
  String? _error, _serviceId;
  bool _private = false, _playlist = false, _busy = false;
  bool _wifiOnly = true;
  late bool _offlineTuner = widget.tvDigital;
  bool _subtitles = false;
  late bool _videoMode = widget.tvDigital;
  bool _serviceActive = false;
  int _revision = 0;
  bool _enabled(MusicSource source) =>
      PersonalScope.maybeOf(context)?.state.settings['source_${source.name}'] !=
      false;

  Future<bool> _requireWifiForStream() async {
    if (!_wifiOnly || _offlineTuner) return true;
    try {
      final transports = await Connectivity().checkConnectivity();
      if (transports.contains(ConnectivityResult.wifi) ||
          transports.contains(ConnectivityResult.ethernet)) {
        return true;
      }
    } catch (_) {
      // Fail closed while Wi-Fi-only mode is enabled.
    }
    if (mounted) {
      setState(
        () => _error =
            'Wi-Fi saja aktif. Sambungkan ke Wi-Fi untuk membuka atau memutar IPTV.',
      );
    }
    return false;
  }

  List<Map<String, dynamic>> get _savedPlaylists {
    final value = PersonalScope.maybeOf(
      context,
    )?.state.settings['saved_iptv_playlists'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['name'] is String && item['text'] is String)
        .toList(growable: false);
  }

  @override
  void dispose() {
    _revision++;
    _input.dispose();
    super.dispose();
  }

  void _select(MusicSource source) {
    if (_busy) return;
    setState(() {
      _source = source;
      _serviceId = null;
      _serviceActive = false;
      _error = null;
      _entries = [];
      _input.clear();
      _revision++;
    });
  }

  Future<void> _open() async {
    if (_busy || !_enabled(_source)) return;
    if (_source == MusicSource.network &&
        !_offlineTuner &&
        !await _requireWifiForStream()) {
      return;
    }
    if (!mounted) return;
    final revision = ++_revision;
    final player = context.read<PlayerCubit>();
    setState(() {
      _busy = true;
      _error = null;
      _serviceId = null;
      _entries = [];
    });
    try {
      if (_source == MusicSource.network) {
        final uri = NetworkPlaylist.address(_input.text);
        if (_offlineTuner && !_isPrivateNetwork(uri)) {
          throw const FormatException(
            'Mode TV Offline hanya menerima alamat tuner di jaringan lokal (alamat IP privat atau .local).',
          );
        }
        final limitation = NetworkPlaylist.limitation(uri, ios: Platform.isIOS);
        if (limitation != null) throw FormatException(limitation);
        final entries = await NetworkResolver().resolve(
          uri,
          forcePlaylist: _playlist,
        );
        if (_offlineTuner &&
            entries.any((entry) => !_isPrivateNetwork(entry.uri))) {
          throw const FormatException(
            'Playlist tuner memuat alamat di luar jaringan lokal. Mode TV Offline hanya memutar stream dari jaringan lokal.',
          );
        }
        if (!mounted || revision != _revision) return;
        setState(() => _entries = entries);
        if (entries.length == 1) {
          if (_videoMode) {
            await _playVideo(entries.single);
          } else {
            await _play(entries);
          }
        }
      } else {
        await player.returnLocal();
        await player.suspendSource();
        if (mounted && revision == _revision) {
          setState(() {
            _serviceId = null;
            _serviceActive = false;
          });
        }
        await _openServiceHome();
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sumber belum dapat dibuka. Periksa alamat, koneksi, dan format media.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isPrivateNetwork(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.local')) return true;
    if (host.contains(':')) {
      return host == '::1' ||
          host.startsWith('fe8') ||
          host.startsWith('fe9') ||
          host.startsWith('fea') ||
          host.startsWith('feb') ||
          host.startsWith('fc') ||
          host.startsWith('fd');
    }
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 169 && b == 254);
  }

  Future<void> _openServiceHome() async {
    final uri = _source == MusicSource.youtube
        ? Uri.https('music.youtube.com', '/')
        : Uri.https('open.spotify.com', '/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _error = 'Aplikasi ${_source.label} tidak dapat dibuka.');
    }
  }

  Future<void> _pickAudioFiles() async {
    if (_busy || !_enabled(MusicSource.network)) return;
    final catalog = context.read<CatalogCubit>();
    final player = context.read<PlayerCubit>();
    final existingIds = catalog.state.tracks.map((track) => track.id).toSet();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await catalog.importFromDevice();
      if (!mounted) return;
      final importedIds = catalog.state.tracks
          .where((track) => !existingIds.contains(track.id))
          .map((track) => track.id)
          .toList(growable: false);
      if (importedIds.isEmpty) {
        setState(
          () => _error =
              catalog.state.message ??
              'Tidak ada file baru untuk diputar. File duplikat sudah ada di Library.',
        );
        return;
      }
      await player.playCollection(importedIds);
      if (mounted) setState(() => _serviceActive = false);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'File tidak dapat diimpor atau diputar. Periksa format audio.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPlaylistFile() async {
    if (_busy || !_enabled(MusicSource.network)) return;
    final personal = PersonalScope.maybeOf(context)?.controller;
    if (personal == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: NetworkPlaylist.extensions.toList(),
        dialogTitle: 'Pilih playlist IPTV',
      );
      if (file == null) return;
      final size = await file.length();
      if (size == null) {
        throw const FormatException('Berkas playlist tidak dapat dibaca.');
      }
      if (size > 2 * 1024 * 1024) {
        throw const FormatException('Playlist terlalu besar (maksimal 2 MB).');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Playlist terlalu besar (maksimal 2 MB).');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final entries = _parseLocalPlaylist(file.name, text);
      if (_offlineTuner &&
          entries.any((entry) => !_isPrivateNetwork(entry.uri))) {
        throw const FormatException(
          'Playlist ini memuat alamat internet. Pilih playlist tuner yang seluruh stream-nya berada di jaringan lokal.',
        );
      }
      final saved = _savedPlaylists
          .where((item) => item['name'] != file.name)
          .toList();
      saved.add({'name': file.name, 'text': text});
      await personal.setting('saved_iptv_playlists', saved);
      if (!mounted) return;
      setState(() => _entries = entries);
      if (entries.length == 1) {
        if (_videoMode) {
          await _playVideo(entries.single);
        } else {
          await _play(entries);
        }
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Playlist tidak dapat dibaca. Pilih file M3U/M3U8 yang valid.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<StreamEntry> _parseLocalPlaylist(String name, String text) {
    final uri = Uri.https('playlist.local', '/$name');
    final entries = NetworkPlaylist.parse(text, uri);
    if (entries.any((entry) => entry.uri.host == 'playlist.local')) {
      throw const FormatException(
        'Playlist berisi alamat relatif. Playlist lokal harus memuat URL HTTP/HTTPS lengkap; alamat relatif bisa dibaca jika playlist dibuka lewat URL server.',
      );
    }
    if (entries.any((entry) => entry.kind == 'hls')) {
      throw const FormatException(
        'File ini adalah manifest HLS. Buka URL manifest .m3u8 dari server, bukan salinan lokalnya.',
      );
    }
    return entries;
  }

  Future<void> _openSavedPlaylist(Map<String, dynamic> playlist) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
    });
    try {
      final entries = _parseLocalPlaylist(
        playlist['name'] as String,
        playlist['text'] as String,
      );
      if (_offlineTuner &&
          entries.any((entry) => !_isPrivateNetwork(entry.uri))) {
        throw const FormatException(
          'Playlist ini memuat alamat internet. Pilih playlist tuner yang seluruh stream-nya berada di jaringan lokal.',
        );
      }
      if (!mounted) return;
      setState(() => _entries = entries);
      if (entries.length == 1) {
        if (_videoMode) {
          await _playVideo(entries.single);
        } else {
          await _play(entries);
        }
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Playlist tersimpan tidak dapat dibaca.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeSavedPlaylist(String name) async {
    final personal = PersonalScope.maybeOf(context)?.controller;
    if (personal == null) return;
    final remaining = _savedPlaylists
        .where((item) => item['name'] != name)
        .toList();
    await personal.setting('saved_iptv_playlists', remaining);
    if (mounted) setState(() {});
  }

  Future<void> _play(List<StreamEntry> entries) async {
    if (!await _requireWifiForStream()) return;
    if (!mounted) return;
    if (_offlineTuner &&
        entries.any((entry) => !_isPrivateNetwork(entry.uri))) {
      throw const FormatException(
        'TV Digital hanya dapat memutar stream dari jaringan lokal.',
      );
    }
    final player = context.read<PlayerCubit>();
    for (final entry in entries) {
      if (entry.kind == 'smooth' || (Platform.isIOS && entry.kind == 'dash')) {
        throw const FormatException(
          'Manifest ini belum didukung pemutar internal pada perangkat ini. Gunakan HLS atau aplikasi eksternal.',
        );
      }
      final limitation = NetworkPlaylist.limitation(
        entry.uri,
        ios: Platform.isIOS,
      );
      if (limitation != null) throw FormatException(limitation);
    }
    final lyrics = _subtitles && entries.length == 1
        ? await NetworkSubtitles().scan(entries.first.uri)
        : null;
    if (!mounted) return;
    await player.openNetwork(
      entries.map((e) => {...e.toJson(), 'lyrics': ?lyrics}).toList(),
      private: _private,
    );
  }

  Future<void> _playSelection(List<StreamEntry> entries) async {
    if (_busy) return;
    if (!await _requireWifiForStream()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      if (entries.length == 1 &&
          entries.first.kind == 'auto' &&
          NetworkPlaylist.extensions.contains(
            NetworkPlaylist.extension(entries.first.uri),
          )) {
        final resolved = await NetworkResolver().resolve(entries.first.uri);
        if (mounted) {
          setState(() => _entries = resolved);
          await _play(resolved);
        }
      } else {
        await _play(entries);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Stream belum dapat diputar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playVideo(StreamEntry entry) async {
    if (!await _requireWifiForStream()) return;
    if (!mounted) return;
    if (_offlineTuner && !_isPrivateNetwork(entry.uri)) {
      setState(
        () => _error =
            'TV Digital hanya dapat memutar stream dari jaringan lokal.',
      );
      return;
    }
    final limitation = NetworkPlaylist.limitation(
      entry.uri,
      ios: Platform.isIOS,
    );
    if (limitation != null) {
      setState(() => _error = limitation);
      return;
    }
    if (!{'http', 'https'}.contains(entry.uri.scheme)) {
      setState(() => _error = 'Video internal memerlukan URL HTTP/HTTPS.');
      return;
    }
    final player = context.read<PlayerCubit>();
    try {
      await player.returnLocal();
      await player.suspendSource();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => VideoStreamScreen(
            uri: entry.uri,
            title: entry.title,
            channels: List.unmodifiable(_entries),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Video belum dapat dibuka. Periksa URL dan codec stream.',
        );
      }
    }
  }

  Future<void> _external() async {
    final player = context.read<PlayerCubit>();
    try {
      final uri = switch (_source) {
        MusicSource.network => NetworkPlaylist.address(_input.text),
        MusicSource.youtube => Uri.https('www.youtube.com', '/watch', {
          'v': ServiceLink.youtube(_input.text),
        }),
        MusicSource.spotify => Uri.https(
          'open.spotify.com',
          '/${ServiceLink.spotify(_input.text)}',
        ),
      };
      setState(() => _serviceId = null);
      await player.returnLocal();
      await player.suspendSource();
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(
          () => _error = 'Tidak ada aplikasi yang dapat membuka protokol ini.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Alamat tidak valid atau aplikasi eksternal belum tersedia.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled(_source);
    if (widget.tvDigital) return _buildDigitalTvScreen(enabled);
    return Scaffold(
      bottomNavigationBar:
          _source == MusicSource.network ||
              _source == MusicSource.youtube ||
              _serviceActive
          ? const SafeArea(child: MiniPlayer())
          : null,
      appBar: AppBar(
        title: Text(widget.tvDigital ? 'TV Digital' : 'Streaming'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!widget.tvDigital)
              Row(
                children: [
                  for (final source in MusicSource.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide.none,
                            backgroundColor: source == _source
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .15)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 2,
                            ),
                          ),
                          onPressed: _busy ? null : () => _select(source),
                          child: Column(
                            children: [
                              SourceIcon(source, selected: source == _source),
                              const SizedBox(height: 8),
                              Text(
                                source.label,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 24),
            Text(
              widget.tvDigital && _source == MusicSource.network
                  ? 'TV Digital'
                  : _source == MusicSource.network
                  ? 'Open Network Stream'
                  : _source == MusicSource.youtube
                  ? 'YouTube Music'
                  : 'Spotify',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_source != MusicSource.network) ...[
              Text(
                _source == MusicSource.youtube
                    ? 'Beranda resmi YouTube Music dengan chart, rekomendasi, dan pencarian.'
                    : 'Cari dan putar lagu di katalog Spotify yang dimuat di sini. Login di situs Spotify bila diminta.',
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            if (!enabled)
              const Text(
                'Sumber dinonaktifkan. Aktifkan melalui pengaturan di atas.',
              ),
            if (_source == MusicSource.network && !widget.tvDigital)
              FilledButton.icon(
                onPressed: enabled && !_busy ? _pickAudioFiles : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.audio_file),
                label: Text(_busy ? 'Mengimpor…' : 'Pilih file musik'),
              ),
            if (_source == MusicSource.network && !widget.tvDigital)
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 12),
                child: Text(
                  'Pilih beberapa file sekaligus: MP3, M4A/AAC, WAV, FLAC, OGG/Opus, WebM dan format audio lain yang didukung perangkat.',
                ),
              ),
            if (_source == MusicSource.network)
              OutlinedButton.icon(
                onPressed: enabled && !_busy ? _pickPlaylistFile : null,
                icon: const Icon(Icons.playlist_add),
                label: Text(
                  widget.tvDigital
                      ? 'Pilih playlist channel M3U'
                      : 'Pilih file playlist M3U/IPTV',
                ),
              ),
            if (_source == MusicSource.network &&
                _savedPlaylists.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Playlist tersimpan'),
              for (final playlist in _savedPlaylists)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.playlist_play),
                  title: Text(playlist['name'] as String),
                  subtitle: const Text('Tersimpan di perangkat'),
                  onTap: _busy ? null : () => _openSavedPlaylist(playlist),
                  trailing: IconButton(
                    tooltip: 'Hapus playlist tersimpan',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy
                        ? null
                        : () =>
                              _removeSavedPlaylist(playlist['name'] as String),
                  ),
                ),
            ],
            if (_source == MusicSource.network)
              TextField(
                controller: _input,
                enabled: enabled && !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _open(),
                decoration: InputDecoration(
                  labelText: _offlineTuner
                      ? 'Alamat tuner / playlist lokal'
                      : 'Alamat stream / playlist',
                  hintText: _offlineTuner
                      ? 'http://192.168.1.1/live.m3u8'
                      : 'https://server.example/radio.m3u',
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_source == MusicSource.network) ...[
              if (widget.tvDigital)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Hubungkan ponsel ke Wi-Fi tuner antena, lalu pilih playlist channel atau masukkan alamat stream lokal dari perangkat tuner.',
                  ),
                ),
              if (!widget.tvDigital)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('TV Offline · tuner lokal'),
                  subtitle: const Text(
                    'Untuk tuner DVB-T2/Wi-Fi yang mengirim HLS atau MP4 di jaringan lokal. Perlu antena dan tuner; tidak memakai internet atau kuota.',
                  ),
                  value: _offlineTuner,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _offlineTuner = value;
                          _error = null;
                          if (value) _videoMode = true;
                        }),
                ),
              if (!widget.tvDigital)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Batasi IPTV internet ke Wi-Fi'),
                  subtitle: const Text(
                    'Blokir pemutaran IPTV saat Wi-Fi tidak tersambung. Playlist internet tetap memerlukan internet melalui Wi-Fi. Untuk memastikan kuota seluler tidak terpakai, matikan data seluler di Quick Settings.',
                  ),
                  value: _wifiOnly,
                  onChanged: _busy || _offlineTuner
                      ? null
                      : (value) => setState(() {
                          _wifiOnly = value;
                          _error = null;
                        }),
                ),
              if (!widget.tvDigital)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Private Playback'),
                  subtitle: const Text(
                    'URL dan antrean stream tidak disimpan; mode privat menyamarkan judul pada kontrol media.',
                  ),
                  value: _private,
                  onChanged: _busy ? null : (v) => setState(() => _private = v),
                ),
              if (!widget.tvDigital)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Baca sebagai playlist'),
                  subtitle: const Text(
                    'Untuk URL tanpa ekstensi, misalnya get.php',
                  ),
                  value: _playlist,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _playlist = v ?? false),
                ),
              if (!widget.tvDigital)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Putar sebagai video IPTV'),
                  subtitle: const Text(
                    'Membuka stream video dalam layar penuh; matikan untuk radio/audio.',
                  ),
                  value: _videoMode,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _videoMode = value),
                ),
              if (!widget.tvDigital)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scan for Subtitles (HTTP-only)'),
                  subtitle: const Text(
                    'Cari .lrc/.vtt/.srt dengan nama sama untuk satu stream; tampil sebagai lirik.',
                  ),
                  value: _subtitles,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _subtitles = v ?? false),
                ),
            ],
            if (_source == MusicSource.youtube && enabled)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YouTube Music di Swift Music',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Beranda, pencarian, dan pemutar resmi YouTube Music.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const ServicePlayerScreen(
                              source: MusicSource.youtube,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        label: const Text('Buka YouTube Music'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_source == MusicSource.spotify && enabled) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Spotify di Swift Music',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Katalog resmi dibuka pada layar pemutar khusus. Login di Spotify bila diminta.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const ServicePlayerScreen(
                              source: MusicSource.spotify,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        label: const Text('Buka katalog dan pemutar Spotify'),
                      ),
                    ],
                  ),
                ),
              ),
              ExpansionTile(
                leading: const Icon(Icons.speaker_group_outlined),
                title: const Text(
                  'Gunakan Swift Music sebagai speaker Spotify',
                ),
                subtitle: const Text('Spotify Connect dari perangkat lain'),
                children: const [SpotifyConnectPanel()],
              ),
            ],
            const SizedBox(height: 12),
            if (_source == MusicSource.network)
              FilledButton.icon(
                key: const Key('open-source-action'),
                onPressed: enabled && !_busy ? _open : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_busy ? 'Membuka…' : 'Open Network Stream'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_source != MusicSource.network)
              TextButton.icon(
                onPressed: !_busy && enabled ? _openServiceHome : null,
                icon: const Icon(Icons.open_in_new),
                label: Text('Buka ${_source.label} di luar Swift Music'),
              ),
            if (_source == MusicSource.network)
              TextButton.icon(
                onPressed: !_busy && enabled ? _external : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Buka melalui aplikasi eksternal'),
              ),
            if (_entries.isNotEmpty) ...[
              Text('${_entries.length} entri playlist'),
              if (_entries.length > 1)
                OutlinedButton(
                  onPressed: _busy ? null : () => _playSelection(_entries),
                  child: const Text('Putar semua'),
                ),
              for (final entry in _entries.take(100))
                ListTile(
                  title: Text(entry.title),
                  subtitle: Text(entry.uri.host),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Putar video fullscreen',
                        icon: const Icon(Icons.ondemand_video),
                        onPressed: _busy ? null : () => _playVideo(entry),
                      ),
                      IconButton(
                        tooltip: 'Putar audio',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: _busy ? null : () => _playSelection([entry]),
                      ),
                    ],
                  ),
                  onTap: _busy
                      ? null
                      : () => _videoMode
                            ? _playVideo(entry)
                            : _playSelection([entry]),
                ),
              if (_entries.length > 100)
                const Text(
                  '100 entri pertama ditampilkan; Putar semua mencakup seluruh daftar.',
                ),
            ],
            if (_serviceId != null && _source != MusicSource.youtube)
              ServicePlayer(
                key: ValueKey('${_source.name}:$_serviceId'),
                source: _source,
                id: _serviceId!,
                sponsorBlock: false,
              ),
            if (_source == MusicSource.network || _serviceActive)
              TextButton(
                onPressed: () async {
                  setState(() {
                    _serviceActive = false;
                    _serviceId = null;
                  });
                  await context.read<PlayerCubit>().returnLocal();
                },
                child: Text(
                  _source == MusicSource.network
                      ? 'Hentikan stream & kembali ke antrean lokal'
                      : 'Tutup sumber & kembali ke antrean lokal',
                ),
              ),
            const SizedBox(height: 16),
            Text(switch (_source) {
              MusicSource.network =>
                'Playlist: M3U/M3U8, XSPF, PLS, WPL, ASX/WAX/WVX. Stream IPTV/video HTTP/HTTPS dapat ditonton fullscreen jika format dan codec didukung perangkat. HLS tersedia pada platform yang didukung. RTSP/RTMP/MMS/FTP/UDP/RTP dan Smooth Streaming masih memerlukan aplikasi eksternal.',
              MusicSource.youtube =>
                'Situs resmi YouTube Music ditampilkan langsung di sini. Google dapat memblokir login dari embedded WebView; playback tetap dikelola YouTube Music, bukan antrean player native Swift Music.',
              MusicSource.spotify =>
                'Pemutar resmi Spotify ditautkan ke sesi Swift Music; kontrol lokal menghentikan sumber ini sebelum mulai lagu lokal. Pengalaman penuh bergantung pada akun dan dukungan resmi Spotify. Aplikasi tidak meminta atau menyimpan kata sandi Spotify.',
            }, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildDigitalTvScreen(bool enabled) {
    final playlists = _savedPlaylists;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        title: const Text('TV Digital'),
        actions: [
          IconButton(
            tooltip: 'Pilih playlist channel',
            onPressed: enabled && !_busy ? _pickPlaylistFile : null,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF030405),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.live_tv_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _entries.isEmpty
                              ? 'TV DIGITAL'
                              : '${_entries.length} CHANNEL SIAP DIPUTAR',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 12),
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daftar channel',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_entries.isNotEmpty)
                    Text(
                      '${_entries.length} channel',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  IconButton(
                    tooltip: 'Tambah playlist',
                    onPressed: enabled && !_busy ? _pickPlaylistFile : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (!enabled)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Aktifkan Open Stream di Library untuk memilih playlist.',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _entries.isNotEmpty
                  ? ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1D382D),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.uri.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Color(0xFF53C878),
                            size: 30,
                          ),
                          onTap: _busy ? null : () => _playVideo(entry),
                        );
                      },
                    )
                  : playlists.isNotEmpty
                  ? ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF1D382D),
                            child: Icon(
                              Icons.playlist_play_rounded,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            playlist['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text(
                            'Playlist tersimpan di perangkat',
                          ),
                          trailing: IconButton(
                            tooltip: 'Hapus playlist',
                            onPressed: _busy
                                ? null
                                : () => _removeSavedPlaylist(
                                    playlist['name'] as String,
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          onTap: _busy
                              ? null
                              : () => _openSavedPlaylist(playlist),
                        );
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.tv_rounded,
                              size: 36,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Belum ada channel',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pilih playlist M3U tuner antena untuk menampilkan channel di sini.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white60),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: enabled && !_busy
                                  ? _pickPlaylistFile
                                  : null,
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: const Text('Pilih playlist channel'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
