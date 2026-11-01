# Swift Music — Listing lengkap implementasi A–D

Baca [README](../README.md) untuk arsitektur, struktur folder, setup, batas demo, dan status verifikasi. Listing ini dihasilkan dari source melalui `node tool/build-guide.cjs`.

## Bagian A — Dependensi, domain, dan data

### pubspec.yaml

```yaml
name: swift_music
description: Cross-platform music player with background playback.
publish_to: none
version: 1.3.0+5
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  audio_service: ^0.18.19
  just_audio: ^0.10.6
  audio_session: ^0.2.4
  flutter_bloc: ^9.1.1
  cached_network_image: ^4.0.5
  salomon_bottom_bar: ^3.3.2
  shared_preferences: ^2.5.6
  file_picker: ^13.3.0
  path_provider: ^2.1.6
  path: ^1.9.1
  crypto: ^3.0.8
  package_info_plus: ^10.2.2
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  flutter_launcher_icons: ^0.14.4
flutter:
  uses-material-design: true
  assets:
    - assets/branding/swift_music_icon.png
```

### lib/features/catalog/domain/track.dart

```dart
/// Domain entity: tidak bergantung pada Flutter atau engine audio.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.audioUrl,
    required this.artUrl,
    required this.lyrics,
    this.duration,
  });
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String audioUrl;
  final String artUrl;
  final String lyrics;
  final Duration? duration;
  bool get isLocal => Uri.tryParse(audioUrl)?.scheme == 'file';
}
```

### lib/features/catalog/domain/catalog_repository.dart

```dart
import 'track.dart';

abstract interface class CatalogRepository {
  List<Track> get tracks;
  List<Track> search(String query, {String? genre});
}

class AudioImportException implements Exception {
  AudioImportException(this.added, this.failed);
  final List<Track> added;
  final int failed;
}

class ImportCancelled implements Exception {}
```

### lib/features/catalog/data/demo_catalog_repository.dart

```dart
import '../domain/catalog_repository.dart';
import '../domain/track.dart';

/// Judul/kategori adalah metadata demo, bukan metadata rekaman komersial.
class DemoCatalogRepository implements CatalogRepository {
  static const _names = [
    'Midnight Bloom',
    'Electric Heart',
    'Slow Sunday',
    'Velvet Skies',
    'After Hours',
    'Golden Coast',
  ];
  static const _artists = [
    'SoundHelix · Demo 1',
    'SoundHelix · Demo 2',
    'SoundHelix · Demo 3',
    'SoundHelix · Demo 4',
    'SoundHelix · Demo 5',
    'SoundHelix · Demo 6',
  ];
  static const _genres = ['Pop', 'Electronic', 'Jazz', 'R&B', 'Rock', 'Chill'];
  static const _photos = [
    'photo-1519681393784-d120267933ba',
    'photo-1470225620780-dba8ba36b745',
    'photo-1516280440614-37939bbacd81',
    'photo-1500530855697-b586d89ba3ee',
    'photo-1493225457124-a3eb161ffa5f',
    'photo-1476514525535-07fb3b4ae5f1',
  ];

  @override
  final List<Track> tracks = List.unmodifiable(
    List.generate(
      6,
      (i) => Track(
        id: 'demo-${i + 1}',
        title: _names[i],
        artist: _artists[i],
        album: ['Night Drive', 'Neon Dreams', 'Sunday Sessions'][i % 3],
        genre: _genres[i],
        audioUrl:
            'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${i + 1}.mp3',
        artUrl:
            'https://images.unsplash.com/${_photos[i]}?w=800&auto=format&fit=crop&q=80',
        lyrics:
            'INSTRUMENTAL DEMO\n\nRekaman contoh SoundHelix.\n'
            'Tidak tersedia lirik untuk lagu ini.\n\n'
            'Area ini siap menampilkan lirik dari katalog Anda.\n'
            'Lirik belum disinkronkan dengan waktu pemutaran.',
      ),
    ),
  );

  @override
  List<Track> search(String query, {String? genre}) {
    final normalized = query.trim().toLowerCase();
    return tracks
        .where(
          (t) =>
              (genre == null || t.genre == genre) &&
              '${t.title} ${t.artist}'.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }
}
```

### lib/features/catalog/data/local_audio_store.dart

```dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../domain/track.dart';
import 'audio_metadata_reader.dart';

/// Salinan permanen di sandbox aplikasi, bukan path cache dari file picker.
/// Metadata menyimpan nama relatif agar tetap valid ketika path sandbox iOS berubah.
class LocalAudioStore {
  LocalAudioStore(
    this.directory, {
    AudioMetadataReader metadata = const NoAudioMetadataReader(),
  }) : _metadata = metadata;
  final Directory directory;
  final AudioMetadataReader _metadata;
  // Containers accepted for import. Actual decoding still depends on the OS.
  static const extensions = [
    'mp3',
    'm4a',
    'aac',
    'wav',
    'wave',
    'flac',
    'ogg',
    'oga',
    'opus',
    'mp4',
    'm4b',
    'mka',
    'webm',
    'amr',
    '3gp',
    'aif',
    'aiff',
    'aifc',
    'caf',
    'ac3',
    'ec3',
    'eac3',
    'mp2',
  ];

  Future<List<Track>> loadTracks() async {
    await directory.create(recursive: true);
    final records = <Map<String, dynamic>>[];
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final record =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        if (record['id'] is! String ||
            record['title'] is! String ||
            record['importedAt'] is! int) {
          continue;
        }
        final filename = record['file'] as String;
        if (!_safeFilename(filename)) continue;
        if (await File(p.join(directory.path, filename)).exists()) {
          if (record['metadataVersion'] != 1 &&
              _metadata is! NoAudioMetadataReader) {
            await _enrich(record);
            await _writeRecord(entry, record);
          }
          records.add(record);
        }
      } catch (_) {
        // Satu metadata rusak tidak menghilangkan lagu lain dari library.
      }
    }
    records.sort(
      (a, b) => (a['importedAt'] as int).compareTo(b['importedAt'] as int),
    );
    return records.map(_track).toList(growable: false);
  }

  bool _safeFilename(String name) =>
      RegExp(r'^[a-f0-9]{64}\.[a-z0-9]+$').hasMatch(name) &&
      extensions.contains(p.extension(name).substring(1));

  Future<Track> importAudio(String name, Stream<List<int>> bytes) async {
    final extension = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!extensions.contains(extension)) {
      throw const FormatException('Format audio tidak didukung.');
    }
    await directory.create(recursive: true);
    final temporary = File(
      p.join(
        directory.path,
        'import-${DateTime.now().microsecondsSinceEpoch}.part',
      ),
    );
    try {
      final sink = temporary.openWrite();
      final digestOutput = _DigestOutput();
      final hasher = sha256.startChunkedConversion(digestOutput);
      try {
        await for (final chunk in bytes) {
          sink.add(chunk);
          hasher.add(chunk);
          // Flushing each bounded chunk supplies backpressure instead of retaining
          // an entire fast file stream in the IOSink buffer.
          await sink.flush();
        }
        hasher.close();
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await temporary.length() == 0) {
        throw const FormatException('File audio kosong.');
      }
      // Hash isi mencegah duplikasi walau nama file berbeda.
      final digest = digestOutput.value!.toString();
      final metadata = File(p.join(directory.path, '$digest.json'));
      if (await metadata.exists()) {
        final previous =
            jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
        if (_safeFilename(previous['file'] as String) &&
            await File(
              p.join(directory.path, previous['file'] as String),
            ).exists()) {
          return _track(previous);
        }
      }
      final filename = '$digest.$extension';
      await temporary.rename(p.join(directory.path, filename));
      final record = <String, dynamic>{
        'id': 'local-$digest',
        'file': filename,
        'title': p.basenameWithoutExtension(name),
        'importedAt': DateTime.now().microsecondsSinceEpoch,
      };
      await _enrich(record);
      // File metadata hanya terlihat setelah penulisan selesai.
      await _writeRecord(metadata, record);
      return _track(record);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _writeRecord(File target, Map<String, dynamic> record) async {
    final pending = File('${target.path}.part');
    await pending.writeAsString(jsonEncode(record), flush: true);
    await pending.rename(target.path);
  }

  Future<void> _enrich(Map<String, dynamic> record) async {
    final audio = File(p.join(directory.path, record['file'] as String));
    final coverName = '${p.basenameWithoutExtension(audio.path)}.cover.jpg';
    final cover = File(p.join(directory.path, coverName));
    try {
      final tags = await _metadata.read(audio, cover);
      for (final key in ['title', 'artist', 'album', 'genre', 'lyrics']) {
        if (tags[key] is String && (tags[key] as String).trim().isNotEmpty) {
          record[key] = (tags[key] as String).trim();
        }
      }
      if (tags['durationMs'] is num && (tags['durationMs'] as num) > 0) {
        record['durationMs'] = tags['durationMs'];
      }
      if (await cover.exists()) record['cover'] = coverName;
    } catch (_) {
      /* Missing or damaged tags never make the audio disappear. */
    }
    record['metadataVersion'] = 1;
  }

  Future<void> remove(String id) async {
    final digest = id.replaceFirst('local-', '');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw ArgumentError('ID lokal tidak valid.');
    }
    final metadata = File(p.join(directory.path, '$digest.json'));
    if (!await metadata.exists()) return;
    final record =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    final filename = record['file'] as String;
    if (!_safeFilename(filename)) {
      throw const FormatException('Metadata file tidak aman.');
    }
    final audio = File(p.join(directory.path, filename));
    if (await audio.exists()) await audio.delete();
    final coverName = record['cover'];
    if (coverName is String &&
        RegExp(r'^[a-f0-9]{64}\.cover\.jpg$').hasMatch(coverName)) {
      final cover = File(p.join(directory.path, coverName));
      if (await cover.exists()) await cover.delete();
    }
    await metadata.delete();
  }

  Track _track(Map<String, dynamic> record) => Track(
    id: record['id'] as String,
    title: record['title'] as String,
    artist: record['artist'] as String? ?? 'Lagu lokal',
    album: record['album'] as String? ?? 'On this device',
    genre: record['genre'] as String? ?? 'Local',
    audioUrl: File(
      p.join(directory.path, record['file'] as String),
    ).uri.toString(),
    artUrl:
        record['cover'] is String &&
            RegExp(
              r'^[a-f0-9]{64}\.cover\.jpg$',
            ).hasMatch(record['cover'] as String)
        ? File(p.join(directory.path, record['cover'] as String)).uri.toString()
        : '',
    lyrics:
        record['lyrics'] as String? ??
        'Lirik belum tersedia untuk file lokal ini.',
    duration: record['durationMs'] is num
        ? Duration(milliseconds: (record['durationMs'] as num).round())
        : null,
  );
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
```

### lib/features/catalog/data/music_folder_source.dart

```dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class MusicFolder {
  const MusicFolder(this.uri, this.name, {this.bookmark});
  final String uri;
  final String name;
  final String? bookmark;
}

class FolderAudioFile {
  const FolderAudioFile(
    this.uri,
    this.name, {
    this.size = -1,
    this.modifiedMs = 0,
  });
  final String uri;
  final String name;
  final int size;
  final int modifiedMs;
  String? fingerprint(String id) =>
      size >= 0 && modifiedMs > 0 ? '$size|$modifiedMs|$id' : null;
}

abstract interface class MusicFolderSource {
  Future<MusicFolder?> pick();
  Future<List<FolderAudioFile>> list(
    MusicFolder folder,
    List<String> extensions,
  );
  Stream<List<int>> read(FolderAudioFile file);
  Future<void> release();
}

abstract interface class RestorableMusicFolderSource
    implements MusicFolderSource {
  Future<MusicFolder> restore(MusicFolder folder);
  Future<void> forget(MusicFolder folder);
}

/// Mobile uses document-provider URIs, never guessed /storage paths.
/// Transfers bounded 64 KiB chunks, with a single open file at a time.
class NativeMusicFolderSource implements RestorableMusicFolderSource {
  NativeMusicFolderSource({MethodChannel? channel, bool? useNative})
    : _channel = channel ?? const MethodChannel('com.swiftmusic/music_folders'),
      _native = useNative ?? (Platform.isAndroid || Platform.isIOS);
  final MethodChannel _channel;
  final bool _native;
  @override
  Future<MusicFolder?> pick() async {
    if (!_native) {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pilih folder musik',
      );
      return path == null
          ? null
          : MusicFolder(Directory(path).uri.toString(), p.basename(path));
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickFolder',
    );
    return result == null
        ? null
        : MusicFolder(
            result['uri'] as String,
            result['name'] as String,
            bookmark: result['bookmark'] as String?,
          );
  }

  @override
  Future<MusicFolder> restore(MusicFolder folder) async {
    if (!_native) {
      if (!await Directory.fromUri(Uri.parse(folder.uri)).exists()) {
        throw const FileSystemException('Folder tidak ditemukan.');
      }
      return folder;
    }
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'restoreFolder',
      {'uri': folder.uri, 'bookmark': folder.bookmark},
    );
    return MusicFolder(
      value!['uri'] as String,
      value['name'] as String,
      bookmark: value['bookmark'] as String?,
    );
  }

  @override
  Future<void> forget(MusicFolder folder) async {
    if (_native) {
      await _channel.invokeMethod<void>('forgetFolder', {'uri': folder.uri});
    }
  }

  @override
  Future<List<FolderAudioFile>> list(
    MusicFolder folder,
    List<String> extensions,
  ) async {
    if (!_native) {
      final files = <FolderAudioFile>[];
      await for (final entry in Directory.fromUri(
        Uri.parse(folder.uri),
      ).list(recursive: true, followLinks: false)) {
        if (entry is File &&
            extensions.contains(
              p.extension(entry.path).replaceFirst('.', '').toLowerCase(),
            )) {
          files.add(
            FolderAudioFile(
              entry.uri.toString(),
              p.basename(entry.path),
              size: await entry.length(),
              modifiedMs: (await entry.lastModified()).millisecondsSinceEpoch,
            ),
          );
        }
      }
      return files;
    }
    final values = await _channel.invokeListMethod<dynamic>('listFolder', {
      'extensions': extensions,
    });
    return values!
        .map((value) {
          final map = Map<String, dynamic>.from(value as Map);
          return FolderAudioFile(
            map['uri'] as String,
            map['name'] as String,
            size: (map['size'] as num?)?.toInt() ?? -1,
            modifiedMs: (map['modifiedMs'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
  }

  @override
  Stream<List<int>> read(FolderAudioFile file) async* {
    if (!_native) {
      yield* File.fromUri(Uri.parse(file.uri)).openRead();
      return;
    }
    final handle = await _channel.invokeMethod<int>('openFile', {
      'uri': file.uri,
    });
    if (handle == null) {
      throw const FileSystemException('File tidak dapat dibuka.');
    }
    try {
      while (true) {
        final bytes = await _channel.invokeMethod<Uint8List>('readChunk', {
          'handle': handle,
        });
        if (bytes == null || bytes.isEmpty) break;
        yield bytes;
      }
    } finally {
      await _channel.invokeMethod<void>('closeFile', {'handle': handle});
    }
  }

  @override
  Future<void> release() async {
    if (_native) await _channel.invokeMethod<void>('releaseFolder');
  }
}
```

### lib/features/catalog/data/device_catalog_repository.dart

```dart
import 'package:file_picker/file_picker.dart';
import '../domain/catalog_repository.dart';
import '../domain/track.dart';
import 'demo_catalog_repository.dart';
import 'local_audio_store.dart';
import 'music_folder_source.dart';
import 'folder_registry.dart';
import '../domain/saved_music_folder.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class DeviceCatalogRepository implements CatalogRepository {
  DeviceCatalogRepository(
    this._store, {
    MusicFolderSource? folders,
    FolderRegistry? registry,
  }) : _folders = folders ?? NativeMusicFolderSource(),
       _registry = registry;
  final LocalAudioStore _store;
  final MusicFolderSource _folders;
  final FolderRegistry? _registry;
  final List<SavedMusicFolder> _savedFolders = [];
  List<SavedMusicFolder> get savedFolders => List.unmodifiable(_savedFolders);
  String? lastImportSummary;
  final List<Track> _tracks = [...DemoCatalogRepository().tracks];
  late final Set<String> _knownIds = _tracks.map((track) => track.id).toSet();
  @override
  List<Track> get tracks => List.unmodifiable(_tracks);

  Future<void> initialize() async {
    _tracks.addAll(await _store.loadTracks());
    _knownIds.addAll(_tracks.map((track) => track.id));
    _savedFolders.addAll(await _registry?.load() ?? []);
  }

  /// Picker sistem: tidak memindai seluruh perangkat atau meminta izin storage luas.
  Future<List<Track>> importFromDevice() async {
    lastImportSummary = null;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: LocalAudioStore.extensions,
    );
    final added = <Track>[];
    var failed = 0;
    var duplicates = 0;
    for (final file in files) {
      try {
        final track = await _store.importAudio(
          file.name,
          file.readAsByteStream(),
        );
        if (!_knownIds.add(track.id)) {
          duplicates++;
          continue;
        }
        _tracks.add(track);
        added.add(track);
      } catch (_) {
        failed++;
      }
    }
    if (files.isNotEmpty) {
      lastImportSummary = _summary(added.length, duplicates, failed);
    }
    if (failed > 0) {
      throw AudioImportException(added, failed);
    }
    return added;
  }

  Future<List<Track>> importFolder(
    void Function(int completed, int total, String folder) progress,
    bool Function() cancelled,
  ) async {
    lastImportSummary = null;
    final folder = await _folders.pick();
    if (folder == null) return [];
    final existing = _savedFolders
        .where((source) => source.uri == folder.uri)
        .firstOrNull;
    final source =
        (existing ??
                SavedMusicFolder(
                  id: sha256.convert(utf8.encode(folder.uri)).toString(),
                  uri: folder.uri,
                  name: folder.name,
                  bookmark: folder.bookmark,
                ))
            .copyWith(excludedIds: {});
    await _saveFolder(source);
    return _scan(folder, source, progress, cancelled);
  }

  Future<List<Track>> rescanFolder(
    String id,
    void Function(int, int, String) progress,
    bool Function() cancelled,
  ) async {
    lastImportSummary = null;
    final source = _savedFolders.firstWhere((folder) => folder.id == id);
    if (_folders is! RestorableMusicFolderSource) {
      throw StateError('Sumber ini tidak dapat dihubungkan ulang.');
    }
    try {
      final restored = await (_folders).restore(
        MusicFolder(source.uri, source.name, bookmark: source.bookmark),
      );
      return await _scan(restored, source, progress, cancelled);
    } catch (error) {
      if (error is AudioImportException) rethrow;
      await _saveFolder(
        source.copyWith(
          lastScanMs: DateTime.now().millisecondsSinceEpoch,
          error:
              'Folder tidak dapat dibaca. Pilih ulang folder jika izin telah berubah.',
        ),
      );
      rethrow;
    }
  }

  Future<void> setAutoScan(String id, bool enabled) async => _saveFolder(
    _savedFolders
        .firstWhere((folder) => folder.id == id)
        .copyWith(autoScan: enabled),
  );

  Future<void> forgetFolder(String id) async {
    final source = _savedFolders.firstWhere((folder) => folder.id == id);
    if (_folders is RestorableMusicFolderSource) {
      await (_folders).forget(
        MusicFolder(source.uri, source.name, bookmark: source.bookmark),
      );
    }
    _savedFolders.removeWhere((folder) => folder.id == id);
    await _registry?.save(_savedFolders);
  }

  Future<void> removeTrack(String id) async {
    await _store.remove(id);
    _tracks.removeWhere((track) => track.id == id);
    _knownIds.remove(id);
    for (final source in [..._savedFolders]) {
      if (source.fingerprints.values.any((value) => value.endsWith('|$id'))) {
        await _saveFolder(
          source.copyWith(excludedIds: {...source.excludedIds, id}),
        );
      }
    }
  }

  Future<void> _saveFolder(SavedMusicFolder source) async {
    final index = _savedFolders.indexWhere((folder) => folder.id == source.id);
    if (index < 0) {
      _savedFolders.add(source);
    } else {
      _savedFolders[index] = source;
    }
    await _registry?.save(_savedFolders);
  }

  Future<List<Track>> _scan(
    MusicFolder folder,
    SavedMusicFolder source,
    void Function(int, int, String) progress,
    bool Function() cancelled,
  ) async {
    final added = <Track>[];
    var duplicates = 0;
    var failed = 0;
    final fingerprints = {...source.fingerprints};
    try {
      progress(0, 0, folder.name);
      final files = await _folders.list(folder, LocalAudioStore.extensions);
      files.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      var completed = 0;
      for (final file in files) {
        if (cancelled()) break;
        try {
          final old = fingerprints[file.uri];
          final previousId = old?.split('|').last;
          if (previousId != null &&
              old == file.fingerprint(previousId) &&
              (_knownIds.contains(previousId) ||
                  source.excludedIds.contains(previousId))) {
            duplicates++;
            completed++;
            progress(completed, files.length, folder.name);
            continue;
          }
          final track = await _store.importAudio(
            file.name,
            _cancellable(_folders.read(file), cancelled),
          );
          final fingerprint = file.fingerprint(track.id);
          // Keep folder membership even when providers omit size/mtime.
          // Such entries are re-read on scans instead of using the fast path.
          fingerprints[file.uri] = fingerprint ?? 'unknown|${track.id}';
          if (source.excludedIds.contains(track.id) &&
              !_knownIds.contains(track.id)) {
            await _store.remove(track.id);
            duplicates++;
          } else if (!_knownIds.add(track.id)) {
            duplicates++;
          } else {
            _tracks.add(track);
            added.add(track);
          }
        } on ImportCancelled {
          break;
        } catch (_) {
          failed++;
        }
        completed++;
        progress(completed, files.length, folder.name);
      }
      lastImportSummary = files.isEmpty
          ? 'Tidak ada file musik yang dikenali di folder ini.'
          : '${cancelled() ? 'Impor dihentikan. ' : ''}${_summary(added.length, duplicates, failed)}';
    } finally {
      await _folders.release();
      await _saveFolder(
        source.copyWith(
          uri: folder.uri,
          name: folder.name,
          bookmark: folder.bookmark,
          lastScanMs: DateTime.now().millisecondsSinceEpoch,
          fingerprints: fingerprints,
          clearError: true,
        ),
      );
    }
    if (failed > 0) throw AudioImportException(added, failed);
    return added;
  }

  Stream<List<int>> _cancellable(
    Stream<List<int>> source,
    bool Function() cancelled,
  ) async* {
    await for (final chunk in source) {
      if (cancelled()) throw ImportCancelled();
      yield chunk;
    }
  }

  String _summary(int added, int duplicates, int failed) =>
      '$added lagu lokal ditambahkan.${duplicates > 0 ? ' $duplicates duplikat dilewati.' : ''}'
      '${failed > 0 ? ' $failed file gagal diimpor.' : ''}';

  @override
  List<Track> search(String query, {String? genre}) {
    final normalized = query.trim().toLowerCase();
    return tracks
        .where(
          (track) =>
              (genre == null || track.genre == genre) &&
              '${track.title} ${track.artist}'.toLowerCase().contains(
                normalized,
              ),
        )
        .toList(growable: false);
  }
}
```

### lib/features/library/data/library_repository.dart

```dart
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LibraryRepository {
  Future<Set<String>> loadLikes();
  Future<void> saveLikes(Set<String> ids);
  Future<List<String>> loadRecent();
  Future<void> saveRecent(List<String> ids);
}

class LocalLibraryRepository implements LibraryRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<Set<String>> loadLikes() async =>
      (await _preferences.getStringList('liked_tracks') ?? []).toSet();
  @override
  Future<void> saveLikes(Set<String> ids) =>
      _preferences.setStringList('liked_tracks', ids.toList());
  @override
  Future<List<String>> loadRecent() async =>
      await _preferences.getStringList('recent_tracks') ?? [];
  @override
  Future<void> saveRecent(List<String> ids) =>
      _preferences.setStringList('recent_tracks', ids);
}
```

### lib/features/catalog/data/audio_metadata_reader.dart

```dart
import 'dart:io';
import 'package:flutter/services.dart';

abstract interface class AudioMetadataReader {
  Future<Map<String, dynamic>> read(File audio, File cover);
}

class NoAudioMetadataReader implements AudioMetadataReader {
  const NoAudioMetadataReader();
  @override
  Future<Map<String, dynamic>> read(File audio, File cover) async => {};
}

class NativeAudioMetadataReader implements AudioMetadataReader {
  const NativeAudioMetadataReader();
  @override
  Future<Map<String, dynamic>> read(File audio, File cover) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {};
    return await const MethodChannel(
          'com.swiftmusic/metadata',
        ).invokeMapMethod<String, dynamic>('read', {
          'path': audio.path,
          'coverPath': cover.path,
        }) ??
        {};
  }
}
```

### lib/features/catalog/data/folder_registry.dart

```dart
import 'dart:convert';
import 'dart:io';
import '../domain/saved_music_folder.dart';

abstract interface class FolderRegistry {
  Future<List<SavedMusicFolder>> load();
  Future<void> save(List<SavedMusicFolder> folders);
}

class FileFolderRegistry implements FolderRegistry {
  FileFolderRegistry(this.file);
  final File file;
  @override
  Future<List<SavedMusicFolder>> load() async {
    if (!await file.exists()) return [];
    final folders = <SavedMusicFolder>[];
    try {
      final values = jsonDecode(await file.readAsString()) as List;
      for (final value in values) {
        try {
          folders.add(
            SavedMusicFolder.fromJson(Map<String, dynamic>.from(value as Map)),
          );
        } catch (_) {
          /* One corrupt folder must not hide other sources. */
        }
      }
    } catch (_) {
      /* Audio copies remain available even if source settings fail. */
    }
    return folders;
  }

  @override
  Future<void> save(List<SavedMusicFolder> folders) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.part');
    await pending.writeAsString(
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
      flush: true,
    );
    await pending.rename(file.path);
  }
}
```

### lib/features/catalog/domain/saved_music_folder.dart

```dart
class SavedMusicFolder {
  SavedMusicFolder({
    required this.id,
    required this.uri,
    required this.name,
    this.bookmark,
    this.lastScanMs = 0,
    this.autoScan = true,
    this.error,
    Map<String, String> fingerprints = const {},
    Set<String> excludedIds = const {},
  }) : fingerprints = Map.unmodifiable(fingerprints),
       excludedIds = Set.unmodifiable(excludedIds);
  final String id;
  final String uri;
  final String name;
  final String? bookmark;
  final int lastScanMs;
  final bool autoScan;
  final String? error;
  final Map<String, String> fingerprints;
  final Set<String> excludedIds;
  SavedMusicFolder copyWith({
    String? uri,
    String? name,
    String? bookmark,
    int? lastScanMs,
    bool? autoScan,
    String? error,
    bool clearError = false,
    Map<String, String>? fingerprints,
    Set<String>? excludedIds,
  }) => SavedMusicFolder(
    id: id,
    uri: uri ?? this.uri,
    name: name ?? this.name,
    bookmark: bookmark ?? this.bookmark,
    lastScanMs: lastScanMs ?? this.lastScanMs,
    autoScan: autoScan ?? this.autoScan,
    error: clearError ? null : error ?? this.error,
    fingerprints: fingerprints ?? this.fingerprints,
    excludedIds: excludedIds ?? this.excludedIds,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri,
    'name': name,
    'bookmark': bookmark,
    'lastScanMs': lastScanMs,
    'autoScan': autoScan,
    'error': error,
    'fingerprints': fingerprints,
    'excludedIds': excludedIds.toList(),
  };
  static SavedMusicFolder fromJson(Map<String, dynamic> json) =>
      SavedMusicFolder(
        id: json['id'] as String,
        uri: json['uri'] as String,
        name: json['name'] as String,
        bookmark: json['bookmark'] as String?,
        lastScanMs: (json['lastScanMs'] as num?)?.toInt() ?? 0,
        autoScan: json['autoScan'] != false,
        error: json['error'] as String?,
        fingerprints: (json['fingerprints'] is Map)
            ? Map<String, String>.from(json['fingerprints'] as Map)
            : {},
        excludedIds: (json['excludedIds'] as List? ?? [])
            .cast<String>()
            .toSet(),
      );
}
```

### lib/features/library/domain/music_playlist.dart

```dart
class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    List<String> trackIds = const [],
    Map<String, String> trackLabels = const {},
  }) : trackIds = List.unmodifiable(trackIds.toSet()),
       trackLabels = Map.unmodifiable(trackLabels);
  final String id;
  final String name;
  final List<String> trackIds;
  final Map<String, String> trackLabels;
  MusicPlaylist copyWith({
    String? name,
    List<String>? trackIds,
    Map<String, String>? trackLabels,
  }) => MusicPlaylist(
    id: id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    trackLabels: trackLabels ?? this.trackLabels,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'trackLabels': trackLabels,
  };
  static MusicPlaylist fromJson(Map<String, dynamic> json) => MusicPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    trackIds: (json['trackIds'] as List).cast<String>(),
    trackLabels: json['trackLabels'] is Map
        ? Map<String, String>.from(json['trackLabels'] as Map)
        : {},
  );
}

enum LibrarySort {
  newest('Terbaru'),
  title('Judul'),
  artist('Artis'),
  album('Album');

  const LibrarySort(this.label);
  final String label;
}
```

### lib/features/library/data/playlist_repository.dart

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/music_playlist.dart';

abstract interface class PlaylistRepository {
  Future<(List<MusicPlaylist>, LibrarySort)> load();
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort);
}

class LocalPlaylistRepository implements PlaylistRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<(List<MusicPlaylist>, LibrarySort)> load() async {
    final raw = await _preferences.getString('music_collections');
    if (raw == null) return (<MusicPlaylist>[], LibrarySort.newest);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final result = <MusicPlaylist>[];
    for (final record in json['playlists'] as List? ?? []) {
      try {
        result.add(
          MusicPlaylist.fromJson(Map<String, dynamic>.from(record as Map)),
        );
      } catch (_) {}
    }
    final sort =
        LibrarySort.values
            .where((value) => value.name == json['sort'])
            .firstOrNull ??
        LibrarySort.newest;
    return (result, sort);
  }

  @override
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort) =>
      _preferences.setString(
        'music_collections',
        jsonEncode({
          'playlists': playlists.map((list) => list.toJson()).toList(),
          'sort': sort.name,
        }),
      );
}

class MemoryPlaylistRepository implements PlaylistRepository {
  List<MusicPlaylist> playlists = [];
  LibrarySort sort = LibrarySort.newest;
  @override
  Future<(List<MusicPlaylist>, LibrarySort)> load() async => (playlists, sort);
  @override
  Future<void> save(List<MusicPlaylist> playlists, LibrarySort sort) async {
    this.playlists = [...playlists];
    this.sort = sort;
  }
}
```

### lib/features/player/domain/lrc_document.dart

```dart
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class LrcDocument {
  LrcDocument._(this.lines);
  final List<LyricLine> lines;
  bool get synced => lines.isNotEmpty;
  static final _timestamp = RegExp(
    r'\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]',
  );
  static LrcDocument parse(String raw) {
    final offsetMatch = RegExp(
      r'\[offset:([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
    final timed = <int, List<String>>{};
    for (final line in raw.replaceAll('\uFEFF', '').split(RegExp(r'\r?\n'))) {
      final stamps = _timestamp.allMatches(line).toList();
      if (stamps.isEmpty) continue;
      final text = line
          .replaceAll(_timestamp, '')
          .replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:\.\d{1,3})?>'), '')
          .trim();
      for (final match in stamps) {
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final ms =
            (int.parse(match.group(1)!) * 60000 +
                    int.parse(match.group(2)!) * 1000 +
                    int.parse(fraction) -
                    offset)
                .clamp(0, 1 << 52);
        final texts = timed.putIfAbsent(ms, () => []);
        if (!texts.contains(text)) texts.add(text);
      }
    }
    final entries = timed.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return LrcDocument._(
      List.unmodifiable(
        entries.map(
          (entry) => LyricLine(
            Duration(milliseconds: entry.key),
            entry.value.join('\n'),
          ),
        ),
      ),
    );
  }

  int activeIndex(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
```

### lib/features/player/data/playback_session_repository.dart

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackSession {
  PlaybackSession({
    required Iterable<String> ids,
    required this.currentId,
    this.positionMs = 0,
    this.volume = 1,
    this.shuffle = false,
    this.repeat = 'none',
  }) : ids = List.unmodifiable(ids.toSet());
  final List<String> ids;
  final String? currentId;
  final int positionMs;
  final double volume;
  final bool shuffle;
  final String repeat;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'ids': ids,
    'currentId': currentId,
    'positionMs': positionMs,
    'volume': volume,
    'shuffle': shuffle,
    'repeat': repeat,
  };
  static PlaybackSession fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['ids'] is! List) {
      throw const FormatException('Sesi tidak valid.');
    }
    final rawPosition = json['positionMs'];
    final rawVolume = json['volume'];
    return PlaybackSession(
      ids: (json['ids'] as List).whereType<String>(),
      currentId: json['currentId'] is String
          ? json['currentId'] as String
          : null,
      positionMs: rawPosition is num && rawPosition.isFinite
          ? rawPosition.toInt().clamp(0, 86400000)
          : 0,
      volume: rawVolume is num && rawVolume.isFinite
          ? rawVolume.toDouble().clamp(0, 1)
          : 1,
      shuffle: json['shuffle'] == true,
      repeat: ['none', 'one', 'all'].contains(json['repeat'])
          ? json['repeat'] as String
          : 'none',
    );
  }

  PlaybackSession reconcile(Set<String> available) {
    final kept = ids.where(available.contains).toList();
    final selected = kept.contains(currentId) ? currentId : kept.firstOrNull;
    return PlaybackSession(
      ids: kept,
      currentId: selected,
      positionMs: selected == currentId ? positionMs : 0,
      volume: volume,
      shuffle: shuffle,
      repeat: repeat,
    );
  }
}

abstract interface class PlaybackSessionRepository {
  Future<PlaybackSession?> load();
  Future<void> save(PlaybackSession session);
}

class LocalPlaybackSessionRepository implements PlaybackSessionRepository {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<PlaybackSession?> load() async {
    final raw = await _preferences.getString('playback_session_v1');
    return raw == null
        ? null
        : PlaybackSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(PlaybackSession session) => _preferences.setString(
    'playback_session_v1',
    jsonEncode(session.toJson()),
  );
}
```

### lib/features/player/domain/sleep_timer.dart

```dart
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
```

### lib/features/library/data/collection_backup.dart

```dart
import 'dart:convert';
import '../domain/music_playlist.dart';

class CollectionBackup {
  CollectionBackup({required this.playlists, required this.likes});
  final List<MusicPlaylist> playlists;
  final Set<String> likes;
  static const maxBytes = 2 * 1024 * 1024;
  List<int> encode() {
    final bytes = utf8.encode(
      jsonEncode({
        'app': 'Swift Music',
        'version': 1,
        'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
        'likes': likes.toList(),
      }),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Cadangan melebihi 2 MiB.');
    }
    decode(bytes); // Never export a backup that this version cannot restore.
    return bytes;
  }

  static CollectionBackup decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Cadangan terlalu besar.');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (json['app'] != 'Swift Music' ||
        json['version'] != 1 ||
        json['playlists'] is! List ||
        json['likes'] is! List) {
      throw const FormatException('Bukan cadangan Swift Music yang didukung.');
    }
    final lists = json['playlists'] as List;
    if (lists.length > 500 || (json['likes'] as List).length > 50000) {
      throw const FormatException('Cadangan terlalu besar.');
    }
    final playlists = lists
        .map(
          (value) =>
              MusicPlaylist.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final ids = <String>{...(json['likes'] as List).cast<String>()};
    var count = ids.length;
    for (final playlist in playlists) {
      if (playlist.trackLabels.length > 50000 ||
          playlist.trackLabels.values.any((label) => label.length > 500)) {
        throw const FormatException('Label lagu tidak valid.');
      }
      if (playlist.name.trim().isEmpty || playlist.name.length > 80) {
        throw const FormatException('Nama playlist tidak valid.');
      }
      ids.addAll(playlist.trackIds);
      count += playlist.trackIds.length;
    }
    if (count > 50000 ||
        ids.any(
          (id) => !RegExp(r'^(local-[a-f0-9]{64}|demo-\d+)$').hasMatch(id),
        )) {
      throw const FormatException('Referensi lagu tidak valid.');
    }
    return CollectionBackup(
      playlists: playlists,
      likes: (json['likes'] as List).cast<String>().toSet(),
    );
  }
}
```

### lib/features/catalog/domain/music_filter.dart

```dart
import 'track.dart';

class MusicFilter {
  const MusicFilter({
    this.folder,
    this.extension,
    this.artist,
    this.album,
    this.duration,
  });
  final String? folder, extension, artist, album, duration;
  bool get active => [
    folder,
    extension,
    artist,
    album,
    duration,
  ].any((value) => value != null);
  bool matches(Track track, {Set<String>? folderTracks}) {
    if (folder != null && !(folderTracks?.contains(track.id) ?? false)) {
      return false;
    }
    if (artist != null &&
        !track.artist.toLowerCase().contains(artist!.trim().toLowerCase())) {
      return false;
    }
    if (album != null &&
        !track.album.toLowerCase().contains(album!.trim().toLowerCase())) {
      return false;
    }
    if (extension != null &&
        Uri.tryParse(track.audioUrl)?.path.split('.').last.toLowerCase() !=
            extension) {
      return false;
    }
    final seconds = track.duration?.inSeconds;
    return switch (duration) {
      'short' => seconds != null && seconds <= 180,
      'long' => seconds != null && seconds > 180,
      'unknown' => seconds == null,
      _ => true,
    };
  }
}
```

## Bagian B — Native Android dan iOS

### native/android/AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <application android:label="Swift Music" android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:enableOnBackInvokedCallback="true">
        <activity android:name=".MainActivity"
            android:exported="true" android:launchMode="singleTop"
            android:taskAffinity="" android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true" android:windowSoftInputMode="adjustResize">
            <meta-data android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback" android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT" />
            <data android:mimeType="text/plain" />
        </intent>
    </queries>
</manifest>
```

### native/android/MainActivity.kt

```kotlin
package com.swiftmusic.swift_music

import com.ryanheise.audioservice.AudioServiceActivity
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.media.MediaMetadataRetriever
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingFolder: MethodChannel.Result? = null
    private var folder: Uri? = null
    private val allowed = mutableSetOf<String>()
    private val streams = mutableMapOf<Int, InputStream>()
    private var nextHandle = 0

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/metadata")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") { result.notImplemented(); return@setMethodCallHandler }
                worker.execute {
                    try {
                        val tags = readMetadata(call)
                        runOnUiThread { result.success(tags) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("metadata", error.message, null) }
                    }
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/music_folders")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFolder") {
                    if (pendingFolder != null) {
                        result.error("picker_busy", "Pemilih folder sedang dibuka.", null)
                    } else {
                        pendingFolder = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, 47021)
                        } catch (error: Exception) {
                            pendingFolder = null
                            result.error("folder_picker", error.message, null)
                        }
                    }
                } else if (call.method in setOf("listFolder", "openFile", "readChunk", "closeFile", "releaseFolder", "restoreFolder", "forgetFolder")) {
                    worker.execute {
                        try {
                            val value = handleFolderCall(call)
                            runOnUiThread { result.success(value) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("folder_io", error.message, null) }
                        }
                    }
                } else result.notImplemented()
            }
    }

    private fun readMetadata(call: MethodCall): Map<String, Any> {
        val root = File(filesDir, "local_music").canonicalFile
        val audio = File(call.argument<String>("path") ?: "").canonicalFile
        val cover = File(call.argument<String>("coverPath") ?: "").canonicalFile
        require(audio.parentFile == root && cover.parentFile == root) { "Path metadata di luar koleksi aplikasi." }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(audio.path)
            val tags = mutableMapOf<String, Any>()
            for ((name, key) in mapOf("title" to MediaMetadataRetriever.METADATA_KEY_TITLE,
                "artist" to MediaMetadataRetriever.METADATA_KEY_ARTIST,
                "album" to MediaMetadataRetriever.METADATA_KEY_ALBUM,
                "genre" to MediaMetadataRetriever.METADATA_KEY_GENRE)) {
                retriever.extractMetadata(key)?.takeIf { it.isNotBlank() }?.let { tags[name] = it }
            }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { tags["durationMs"] = it }
            val image = retriever.embeddedPicture
            if (image != null && image.size <= 8 * 1024 * 1024) {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(image, 0, image.size, bounds)
                var sample = 1
                while (bounds.outWidth / sample > 768 || bounds.outHeight / sample > 768) sample *= 2
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                BitmapFactory.decodeByteArray(image, 0, image.size, options)?.let { bitmap ->
                    try { cover.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it) } }
                    finally { bitmap.recycle() }
                }
            }
            return tags
        } finally { retriever.release() }
    }

    @Deprecated("Used for the system document tree picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 47021) return
        val reply = pendingFolder ?: return
        pendingFolder = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { reply.success(null); return }
        folder = uri
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        catch (_: SecurityException) { /* Temporary access still permits this import. */ }
        val id = DocumentsContract.getTreeDocumentId(uri)
        reply.success(mapOf("uri" to uri.toString(), "name" to id.substringAfter(':').substringAfterLast('/').ifEmpty { "Musik" }))
    }

    private fun handleFolderCall(call: MethodCall): Any? = when (call.method) {
        "restoreFolder" -> {
            val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong."))
            require(contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) { "Izin folder telah berakhir. Pilih ulang folder." }
            folder = uri
            val id = DocumentsContract.getTreeDocumentId(uri)
            mapOf("uri" to uri.toString(), "name" to id.substringAfter(':').substringAfterLast('/').ifEmpty { "Musik" })
        }
        "forgetFolder" -> {
            val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong."))
            if (contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) {
                contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            null
        }
        "listFolder" -> {
            val root = folder ?: throw IllegalStateException("Pilih folder terlebih dahulu.")
            val extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
            val files = mutableListOf<Map<String, Any>>()
            val directories = java.util.ArrayDeque<String>()
            val visited = mutableSetOf<String>()
            directories.add(DocumentsContract.getTreeDocumentId(root))
            allowed.clear()
            while (!directories.isEmpty()) {
                val id = directories.removeFirst()
                if (!visited.add(id)) continue
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(root, id)
                contentResolver.query(children, arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                ), null, null, null).use { cursor ->
                    if (cursor == null) throw java.io.IOException("Folder tidak dapat dibaca.")
                    while (cursor.moveToNext()) {
                        val childId = cursor.getString(0)
                        val name = cursor.getString(1) ?: continue
                        if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                            directories.add(childId)
                        } else if (name.substringAfterLast('.', "").lowercase(Locale.ROOT) in extensions) {
                            val uri = DocumentsContract.buildDocumentUriUsingTree(root, childId).toString()
                            allowed.add(uri)
                            files.add(mapOf("uri" to uri, "name" to name,
                                "size" to if (cursor.isNull(3)) -1L else cursor.getLong(3),
                                "modifiedMs" to if (cursor.isNull(4)) 0L else cursor.getLong(4)))
                        }
                    }
                }
            }
            files
        }
        "openFile" -> {
            val uri = call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong.")
            require(uri in allowed) { "File tidak berasal dari folder pilihan." }
            val stream = contentResolver.openInputStream(Uri.parse(uri)) ?: throw java.io.IOException("File tidak dapat dibuka.")
            val handle = ++nextHandle
            streams[handle] = stream
            handle
        }
        "readChunk" -> {
            val stream = streams[call.argument<Int>("handle")] ?: throw java.io.IOException("File sudah ditutup.")
            val buffer = ByteArray(65536)
            val length = stream.read(buffer)
            if (length <= 0) null else if (length == buffer.size) buffer else buffer.copyOf(length)
        }
        "closeFile" -> { streams.remove(call.argument<Int>("handle"))?.close(); null }
        "releaseFolder" -> {
            streams.values.forEach { try { it.close() } catch (_: Exception) {} }
            streams.clear(); allowed.clear(); folder = null; null
        }
        else -> null
    }

    override fun onDestroy() {
        worker.execute {
            streams.values.forEach { try { it.close() } catch (_: Exception) {} }
            streams.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }
    // Flutter menangani route/tab terlebih dahulu. Hanya Back di root yang
    // mencapai callback ini; pertahankan activity dan engine audio di background.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
}
```

### native/android/ic_stat_music_note.xml

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M12,3v10.55C11.41,13.21 10.73,13 10,13c-2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z" />
</vector>
```

### native/android/keep.xml

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_music_note,@drawable/audio_service_*" />
```

### native/ios/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key><string>Swift Music</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>swift_music</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(FLUTTER_BUILD_NAME)</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleVersion</key><string>$(FLUTTER_BUILD_NUMBER)</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UIBackgroundModes</key><array><string>audio</string></array>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key><false/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneClassName</key><string>UIWindowScene</string>
                    <key>UISceneConfigurationName</key><string>flutter</string>
                    <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
                    <key>UISceneStoryboardFile</key><string>Main</string>
                </dict>
            </array>
        </dict>
    </dict>
    <key>UILaunchStoryboardName</key><string>LaunchScreen</string>
    <key>UIMainStoryboardFile</key><string>Main</string>
    <key>UISupportedInterfaceOrientations</key>
    <array><string>UIInterfaceOrientationPortrait</string>
      <string>UIInterfaceOrientationLandscapeLeft</string>
      <string>UIInterfaceOrientationLandscapeRight</string></array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array><string>UIInterfaceOrientationPortrait</string>
      <string>UIInterfaceOrientationPortraitUpsideDown</string>
      <string>UIInterfaceOrientationLandscapeLeft</string>
      <string>UIInterfaceOrientationLandscapeRight</string></array>
    <key>CADisableMinimumFrameDurationOnPhone</key><true/>
    <key>UIApplicationSupportsIndirectInputEvents</key><true/>
</dict>
</plist>
```

### native/ios/AppDelegate.swift

```swift
import Flutter
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var musicFolders: MusicFolderBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    musicFolders = MusicFolderBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Keeps security-scoped access only while copying the selected folder.
private final class MusicFolderBridge: NSObject, UIDocumentPickerDelegate {
  private let worker = DispatchQueue(label: "com.swiftmusic.folder-io", qos: .utility)
  private var pending: FlutterResult?
  private var folder: URL?
  private var hasScope = false
  private var allowed = Set<String>()
  private var handles = [Int: FileHandle]()
  private var nextHandle = 0
  private var channel: FlutterMethodChannel!
  private var metadataChannel: FlutterMethodChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    metadataChannel = FlutterMethodChannel(name: "com.swiftmusic/metadata", binaryMessenger: messenger)
    metadataChannel.setMethodCallHandler { [self] call, result in
      guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
      worker.async { [self] in
        do {
          let tags = try readMetadata(call)
          DispatchQueue.main.async { result(tags) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "metadata", message: error.localizedDescription, details: nil)) }
        }
      }
    }
    channel = FlutterMethodChannel(name: "com.swiftmusic/music_folders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [self] call, result in
      if call.method == "pickFolder" { pick(result); return }
      guard ["listFolder", "openFile", "readChunk", "closeFile", "releaseFolder", "restoreFolder", "forgetFolder"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      worker.async { [self] in
        do {
          let value = try handle(call)
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "folder_io", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }

  private func readMetadata(_ call: FlutterMethodCall) throws -> [String: Any] {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let path = args["path"] as? String, let coverPath = args["coverPath"] as? String else { throw FolderError.notAllowed }
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("local_music").standardizedFileURL.resolvingSymlinksInPath()
    let audio = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let cover = URL(fileURLWithPath: coverPath).standardizedFileURL.resolvingSymlinksInPath()
    guard audio.deletingLastPathComponent() == root, cover.deletingLastPathComponent() == root else { throw FolderError.notAllowed }
    let asset = AVURLAsset(url: audio)
    var tags = [String: Any]()
    for item in asset.commonMetadata {
      if let key = item.commonKey?.rawValue, ["title", "artist", "albumName", "type"].contains(key), let value = item.stringValue {
        tags[key == "albumName" ? "album" : key == "type" ? "genre" : key] = value
      }
      if item.commonKey == .commonKeyArtwork, let data = item.dataValue, data.count <= 8 * 1024 * 1024,
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 768,
          kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) {
        try UIImage(cgImage: image).jpegData(compressionQuality: 0.82)?.write(to: cover, options: .atomic)
      }
    }
    let seconds = CMTimeGetSeconds(asset.duration)
    if seconds.isFinite && seconds > 0 { tags["durationMs"] = Int(seconds * 1000) }
    return tags
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "picker_busy", message: "Pemilih folder sedang dibuka.", details: nil)); return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "folder_picker", message: "Jendela aplikasi tidak tersedia.", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil); pending = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { documentPickerWasCancelled(controller); return }
    folder = url
    hasScope = url.startAccessingSecurityScopedResource()
    let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    pending?(["uri": url.absoluteString, "name": url.lastPathComponent, "bookmark": bookmark?.base64EncodedString() ?? ""])
    pending = nil
  }

  private func handle(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "restoreFolder":
      guard let encoded = args["bookmark"] as? String, let data = Data(base64Encoded: encoded) else { throw FolderError.notAllowed }
      var stale = false
      let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
      folder = url
      hasScope = url.startAccessingSecurityScopedResource()
      let renewed = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      return ["uri": url.absoluteString, "name": url.lastPathComponent, "bookmark": renewed.base64EncodedString()]
    case "forgetFolder": return nil
    case "listFolder":
      guard let root = folder else { throw FolderError.notSelected }
      let extensions = Set(args["extensions"] as? [String] ?? [])
      let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
      guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw FolderError.notSelected }
      allowed.removeAll()
      var files = [[String: Any]]()
      for case let url as URL in entries {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true, values.isSymbolicLink != true,
          extensions.contains(url.pathExtension.lowercased()) else { continue }
        allowed.insert(url.absoluteString)
        files.append(["uri": url.absoluteString, "name": url.lastPathComponent,
          "size": values.fileSize ?? -1, "modifiedMs": Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)])
      }
      return files
    case "openFile":
      guard let uri = args["uri"] as? String, allowed.contains(uri), let url = URL(string: uri) else {
        throw FolderError.notAllowed
      }
      nextHandle += 1
      handles[nextHandle] = try FileHandle(forReadingFrom: url)
      return nextHandle
    case "readChunk":
      guard let id = args["handle"] as? Int, let file = handles[id] else { throw FolderError.missingHandle }
      guard let bytes = try file.read(upToCount: 65536), !bytes.isEmpty else { return nil }
      return FlutterStandardTypedData(bytes: bytes)
    case "closeFile":
      if let id = args["handle"] as? Int { try handles.removeValue(forKey: id)?.close() }
      return nil
    case "releaseFolder":
      for file in handles.values { try? file.close() }
      handles.removeAll(); allowed.removeAll()
      if hasScope { folder?.stopAccessingSecurityScopedResource() }
      folder = nil; hasScope = false
      return nil
    default: return FlutterMethodNotImplemented
    }
  }
  private enum FolderError: Error { case notSelected, notAllowed, missingHandle }
}
```

## Bagian C — Handler dan state management

### lib/features/player/data/swift_audio_handler.dart

```dart
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

  void _publishCustom() => customState.add({
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
    if (!_sessionReady || _mutating) return;
    final session = PlaybackSession(
      ids: _items.map((item) => item.id),
      currentId: mediaItem.value?.id,
      positionMs: (_loaded ? _player.position : _resumePosition).inMilliseconds,
      volume: _player.volume,
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
        if (_mutating) return;
        if (index != null && index < _items.length) {
          mediaItem.add(_items[index]);
          unawaited(_saveSession());
        }
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (_mutating) return;
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
    if (name == 'setVolume') {
      final value = extras?['volume'];
      if (value is! num || !value.isFinite) {
        throw ArgumentError('Volume harus berupa angka finite.');
      }
      await _player.setVolume(value.toDouble().clamp(0.0, 1.0));
      await _saveSession();
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

  Future<void> _editQueue(Future<void> Function() operation) {
    final completion = Completer<void>();
    _queueTail = _queueTail.catchError((_) {}).then((_) async {
      final selectedId = mediaItem.value?.id;
      try {
        await _preparing;
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
        _items
            .map(
              (item) => AudioSource.uri(
                Uri.parse(item.extras!['url'] as String),
                tag: item,
              ),
            )
            .toList(),
        initialIndex: index,
        initialPosition: _resumePosition,
      );
      _loaded = true;
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
    _sleep.cancel();
    await _releaseEndGuard();
    await _saveSession();
    _failed = false;
    await _player.stop();
    await super.stop();
  }

  /// Hanya untuk teardown pemilik service/test, bukan saat modal ditutup.
  Future<void> dispose() async {
    _checkpoint?.cancel();
    _sleep.dispose();
    await _saveSession();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }
}
```

### lib/features/player/presentation/player_cubit.dart

```dart
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
  Future<void> playId(String id) => _run(() async {
    await _handler.customAction('playId', {'id': id});
  });
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
```

### lib/features/player/presentation/artwork_style_cubit.dart

```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ArtworkStyle {
  cover('Cover', 'Sampul album klasik'),
  lyrics('Lirik', 'Lirik yang dapat digulir dan ditambahkan sendiri'),
  vinyl('Vinyl', 'Piringan berputar saat lagu dimainkan'),
  spectrum('Spectrum', 'Lingkaran spektrum neon biru dan magenta'),
  wave('Wave', 'Gelombang cahaya berlapis yang mengalir'),
  pulse('Pulse', 'Sampul dengan denyut cahaya lembut');

  const ArtworkStyle(this.label, this.description);
  final String label;
  final String description;
}

class ArtworkStyleState {
  const ArtworkStyleState({
    this.style = ArtworkStyle.cover,
    this.saving = false,
    this.error,
  });
  final ArtworkStyle style;
  final bool saving;
  final String? error;
}

class ArtworkStyleCubit extends Cubit<ArtworkStyleState> {
  ArtworkStyleCubit({
    Future<String?> Function()? load,
    Future<void> Function(String)? save,
  }) : _load = load ?? (() => SharedPreferencesAsync().getString(_key)),
       _save =
           save ?? ((value) => SharedPreferencesAsync().setString(_key, value)),
       super(const ArtworkStyleState()) {
    unawaited(_restore());
  }
  static const _key = 'player_artwork_style';
  final Future<String?> Function() _load;
  final Future<void> Function(String) _save;
  bool _selected = false;
  bool _persisting = false;
  ArtworkStyle? _pending;

  Future<void> next() => select(
    ArtworkStyle.values[(ArtworkStyle.values.indexOf(state.style) + 1) %
        ArtworkStyle.values.length],
  );

  Future<void> _restore() async {
    try {
      final saved = await _load();
      if (isClosed || _selected) return;
      final style = ArtworkStyle.values
          .where((style) => style.name == saved)
          .firstOrNull;
      if (style != null) emit(ArtworkStyleState(style: style));
    } catch (_) {
      // Preferensi gagal dibaca tidak boleh menghalangi pemutar audio.
    }
  }

  Future<void> select(ArtworkStyle style) async {
    if (isClosed) return;
    _selected = true;
    _pending = style;
    emit(ArtworkStyleState(style: style, saving: true));
    if (_persisting) return;
    _persisting = true;
    String? error;
    while (_pending != null && !isClosed) {
      final target = _pending!;
      _pending = null;
      try {
        await _save(target.name);
        error = null;
      } catch (_) {
        error = 'Pilihan diterapkan, tetapi belum berhasil disimpan.';
      }
    }
    _persisting = false;
    if (!isClosed) emit(ArtworkStyleState(style: state.style, error: error));
  }
}
```

### lib/features/library/presentation/library_cubit.dart

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/library_repository.dart';

class LibraryState {
  LibraryState({
    Set<String> likes = const {},
    List<String> recent = const [],
    this.error,
  }) : likes = Set.unmodifiable(likes),
       recent = List.unmodifiable(recent);
  final Set<String> likes;
  final List<String> recent;
  final String? error;
}

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._repository) : super(LibraryState());
  final LibraryRepository _repository;
  Future<void> mergeLikes(Set<String> incoming) async {
    final likes = {...state.likes, ...incoming};
    await _repository.saveLikes(likes);
    if (!isClosed) emit(LibraryState(likes: likes, recent: state.recent));
  }

  Future<void> removeTrack(String id) async {
    final likes = {...state.likes}..remove(id);
    final recent = state.recent.where((track) => track != id).toList();
    emit(LibraryState(likes: likes, recent: recent));
    try {
      await _repository.saveLikes(likes);
      await _repository.saveRecent(recent);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Perubahan Library belum tersimpan.',
          ),
        );
      }
    }
  }

  Future<void> initialize() async {
    try {
      final likes = await _repository.loadLikes();
      final recent = await _repository.loadRecent();
      if (!isClosed) emit(LibraryState(likes: likes, recent: recent));
    } catch (_) {
      if (!isClosed) {
        emit(LibraryState(error: 'Penyimpanan lokal tidak tersedia.'));
      }
    }
  }

  Future<void> toggleLike(String id) async {
    final likes = {...state.likes};
    likes.contains(id) ? likes.remove(id) : likes.add(id);
    emit(LibraryState(likes: likes, recent: state.recent));
    try {
      await _repository.saveLikes(likes);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Favorit belum tersimpan ke perangkat.',
          ),
        );
      }
    }
  }

  Future<void> recordPlay(String id) async {
    if (state.recent.isNotEmpty && state.recent.first == id) return;
    final recent = [
      id,
      ...state.recent.where((item) => item != id),
    ].take(6).toList();
    emit(LibraryState(likes: state.likes, recent: recent));
    try {
      await _repository.saveRecent(recent);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Riwayat belum tersimpan ke perangkat.',
          ),
        );
      }
    }
  }
}
```

### lib/features/catalog/presentation/catalog_cubit.dart

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/catalog_repository.dart';
import '../domain/saved_music_folder.dart';
import '../domain/track.dart';

typedef ImportProgress = void Function(int, int, String);

class CatalogState {
  CatalogState({
    required List<Track> tracks,
    this.importing = false,
    this.message,
    this.completed = 0,
    this.total = 0,
    this.folder,
    this.cancelling = false,
    List<SavedMusicFolder> sources = const [],
  }) : tracks = List.unmodifiable(tracks),
       sources = List.unmodifiable(sources);
  final List<Track> tracks;
  final bool importing;
  final String? message;
  final int completed;
  final int total;
  final String? folder;
  final bool cancelling;
  final List<SavedMusicFolder> sources;
}

class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(
    this._repository, {
    Future<List<Track>> Function()? importAudio,
    Future<void> Function(List<Track>)? onAdded,
    Future<List<Track>> Function(ImportProgress, bool Function())? importFolder,
    String? Function()? summary,
    List<SavedMusicFolder> Function()? folders,
    Future<List<Track>> Function(String, ImportProgress, bool Function())?
    rescan,
    Future<void> Function(String)? forget,
    Future<void> Function(String, bool)? setAutoScan,
    Future<void> Function(String)? removeTrack,
    Future<void> Function(String)? onRemoved,
  }) : _importAudio = importAudio,
       _onAdded = onAdded,
       _importFolder = importFolder,
       _summary = summary,
       _folders = folders,
       _rescan = rescan,
       _forget = forget,
       _setAutoScan = setAutoScan,
       _removeTrack = removeTrack,
       _onRemoved = onRemoved,
       super(
         CatalogState(
           tracks: _repository.tracks,
           sources: folders?.call() ?? [],
         ),
       );
  final CatalogRepository _repository;
  final Future<List<Track>> Function()? _importAudio;
  final Future<void> Function(List<Track>)? _onAdded;
  final Future<List<Track>> Function(ImportProgress, bool Function())?
  _importFolder;
  final String? Function()? _summary;
  final List<SavedMusicFolder> Function()? _folders;
  final Future<List<Track>> Function(String, ImportProgress, bool Function())?
  _rescan;
  final Future<void> Function(String)? _forget;
  final Future<void> Function(String, bool)? _setAutoScan;
  final Future<void> Function(String)? _removeTrack;
  final Future<void> Function(String)? _onRemoved;
  bool _cancelled = false;
  bool get canRemove => _removeTrack != null;
  CatalogState _snapshot({
    bool importing = false,
    String? message,
    int completed = 0,
    int total = 0,
    String? folder,
    bool cancelling = false,
    List<Track>? tracks,
  }) => CatalogState(
    tracks: tracks ?? _repository.tracks,
    importing: importing,
    message: message,
    completed: completed,
    total: total,
    folder: folder,
    cancelling: cancelling,
    sources: _folders?.call() ?? [],
  );
  void cancelImport() {
    if (!state.importing || isClosed) return;
    _cancelled = true;
    emit(
      _snapshot(
        tracks: state.tracks,
        importing: true,
        completed: state.completed,
        total: state.total,
        folder: state.folder,
        cancelling: true,
      ),
    );
  }

  Future<void> importFromDevice() => _import(false);
  Future<void> importFromFolder() => _import(true);
  Future<void> rescanFolder(String id) => _import(true, sourceId: id);
  Future<void> checkSavedFolders() async {
    if (isClosed || state.importing || _rescan == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final folder in [...state.sources]) {
      if (!folder.autoScan ||
          folder.error != null ||
          now - folder.lastScanMs < 60000) {
        continue;
      }
      await _import(true, sourceId: folder.id, automatic: true);
      if (_cancelled || isClosed) break;
    }
  }

  Future<void> forgetFolder(String id) async {
    if (state.importing || _forget == null) return;
    try {
      await _forget(id);
      if (!isClosed) {
        emit(
          _snapshot(message: 'Sumber folder dilepas. Salinan lagu tetap ada.'),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(_snapshot(message: 'Sumber folder belum dapat dilepas.'));
      }
    }
  }

  Future<void> setAutoScan(String id, bool enabled) async {
    if (state.importing || _setAutoScan == null) return;
    try {
      await _setAutoScan(id, enabled);
      if (!isClosed) emit(_snapshot());
    } catch (_) {
      if (!isClosed) {
        emit(_snapshot(message: 'Pengaturan folder belum tersimpan.'));
      }
    }
  }

  Future<void> removeLocalTrack(String id) async {
    if (state.importing || _removeTrack == null) return;
    try {
      await _removeTrack(id);
      await _onRemoved?.call(id);
      if (!isClosed) {
        emit(
          _snapshot(
            message: 'Lagu dihapus dari Library. File asli tidak diubah.',
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(_snapshot(message: 'Lagu belum dapat dihapus. Coba lagi.'));
      }
    }
  }

  Future<void> _import(
    bool folder, {
    String? sourceId,
    bool automatic = false,
  }) async {
    if (state.importing ||
        isClosed ||
        (sourceId != null
            ? _rescan == null
            : folder
            ? _importFolder == null
            : _importAudio == null)) {
      return;
    }
    _cancelled = false;
    emit(_snapshot(importing: true));
    var added = <Track>[];
    String? message;
    var failed = false;
    final progressClock = Stopwatch()..start();
    void progress(int completed, int total, String name) {
      if (!isClosed &&
          (total == 0 ||
              completed == total ||
              progressClock.elapsedMilliseconds >= 100)) {
        progressClock.reset();
        emit(
          _snapshot(
            tracks: state.tracks,
            importing: true,
            completed: completed,
            total: total,
            folder: name,
            cancelling: _cancelled,
          ),
        );
      }
    }

    try {
      added = sourceId != null
          ? await _rescan!(sourceId, progress, () => _cancelled || isClosed)
          : folder
          ? await _importFolder!(progress, () => _cancelled || isClosed)
          : await _importAudio!();
      if (added.isNotEmpty) message = '${added.length} lagu lokal ditambahkan.';
    } on AudioImportException catch (error) {
      failed = true;
      added = error.added;
      message =
          '${added.length} lagu ditambahkan; ${error.failed} file gagal diimpor.';
    } catch (_) {
      failed = true;
      message = sourceId != null
          ? 'Folder tidak dapat diakses. Hubungkan ulang melalui Pilih folder musik.'
          : 'Tidak dapat membaca pilihan ini. Coba pilih folder/file lain.';
    }
    message = _summary?.call() ?? message;
    if (automatic && added.isEmpty && !failed) message = null;
    try {
      if (added.isNotEmpty) await _onAdded?.call(added);
    } catch (_) {
      message =
          'Lagu tersimpan. Antrean audio belum diperbarui; buka ulang aplikasi.';
    }
    if (!isClosed) emit(_snapshot(message: message));
  }
}
```

### lib/features/library/presentation/playlist_cubit.dart

```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../data/playlist_repository.dart';
import '../domain/music_playlist.dart';

class PlaylistState {
  PlaylistState({
    List<MusicPlaylist> playlists = const [],
    this.sort = LibrarySort.newest,
    this.error,
  }) : playlists = List.unmodifiable(playlists);
  final List<MusicPlaylist> playlists;
  final LibrarySort sort;
  final String? error;
}

class PlaylistCubit extends Cubit<PlaylistState> {
  PlaylistCubit(this._repository) : super(PlaylistState()) {
    _ready = _initialize();
  }
  final PlaylistRepository _repository;
  late final Future<void> _ready;
  Future<void> _writes = Future.value();
  int _revision = 0;
  int _nextId = 0;
  Future<void> _initialize() async {
    try {
      final (playlists, sort) = await _repository.load();
      if (!isClosed) emit(PlaylistState(playlists: playlists, sort: sort));
    } catch (_) {
      if (!isClosed) {
        emit(PlaylistState(error: 'Playlist tersimpan belum dapat dibaca.'));
      }
    }
  }

  Future<void> _persist() async {
    final revision = ++_revision;
    final lists = state.playlists;
    final sort = state.sort;
    _writes = _writes
        .catchError((_) {})
        .then((_) => _repository.save(lists, sort));
    try {
      await _writes;
    } catch (_) {
      if (!isClosed && revision == _revision) {
        emit(
          PlaylistState(
            playlists: state.playlists,
            sort: state.sort,
            error: 'Perubahan playlist belum tersimpan. Coba lagi.',
          ),
        );
      }
    }
  }

  Future<String?> create(String name) async {
    await _ready;
    name = name.trim();
    if (isClosed || name.isEmpty || name.length > 80) return null;
    final id = 'playlist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    emit(
      PlaylistState(
        playlists: [
          ...state.playlists,
          MusicPlaylist(id: id, name: name),
        ],
        sort: state.sort,
      ),
    );
    await _persist();
    return id;
  }

  Future<void> rename(String id, String name) async {
    await _ready;
    if (name.trim().isEmpty || name.trim().length > 80 || isClosed) return;
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (list) => list.id == id ? list.copyWith(name: name.trim()) : list,
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> delete(String id) async {
    await _ready;
    if (isClosed) return;
    emit(
      PlaylistState(
        playlists: state.playlists.where((list) => list.id != id).toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<int> mergeBackup(List<MusicPlaylist> incoming) async {
    await _ready;
    if (isClosed) return 0;
    final lists = [...state.playlists];
    var added = 0;
    for (final playlist in incoming) {
      if (lists.any(
        (existing) =>
            existing.name == playlist.name &&
            existing.trackIds.join('|') == playlist.trackIds.join('|'),
      )) {
        continue;
      }
      lists.add(
        MusicPlaylist(
          id: 'playlist-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
          name: playlist.name,
          trackIds: playlist.trackIds,
          trackLabels: playlist.trackLabels,
        ),
      );
      added++;
    }
    emit(PlaylistState(playlists: lists, sort: state.sort));
    await _persist();
    return added;
  }

  Future<void> setTracks(String id, List<String> ids) async {
    await _ready;
    if (isClosed) return;
    emit(
      PlaylistState(
        playlists: state.playlists
            .map((list) => list.id == id ? list.copyWith(trackIds: ids) : list)
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> addTrack(String id, String trackId) async {
    await _ready;
    final list = state.playlists.where((list) => list.id == id).firstOrNull;
    if (list != null) await setTracks(id, [...list.trackIds, trackId]);
  }

  Future<void> removeTrackEverywhere(String id) async {
    await _ready;
    if (isClosed) return;
    emit(
      PlaylistState(
        playlists: state.playlists
            .map(
              (list) => list.copyWith(
                trackIds: list.trackIds
                    .where((trackId) => trackId != id)
                    .toList(),
              ),
            )
            .toList(),
        sort: state.sort,
      ),
    );
    await _persist();
  }

  Future<void> setSort(LibrarySort sort) async {
    await _ready;
    if (!isClosed) {
      emit(PlaylistState(playlists: state.playlists, sort: sort));
      await _persist();
    }
  }

  List<Track> sorted(Iterable<Track> tracks) {
    final result = tracks.toList();
    if (state.sort == LibrarySort.newest) return result.reversed.toList();
    String key(Track track) => switch (state.sort) {
      LibrarySort.artist => track.artist,
      LibrarySort.album => track.album,
      _ => track.title,
    };
    result.sort((a, b) => key(a).toLowerCase().compareTo(key(b).toLowerCase()));
    return result;
  }

  @override
  Future<void> close() async {
    await _writes.catchError((_) {});
    return super.close();
  }
}
```

## Bagian D — Entry point dan antarmuka lengkap

### lib/main.dart

```dart
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app/main_screen.dart';
import 'core/theme/app_theme.dart';
import 'features/catalog/domain/catalog_repository.dart';
import 'features/catalog/data/device_catalog_repository.dart';
import 'features/catalog/data/local_audio_store.dart';
import 'features/catalog/data/audio_metadata_reader.dart';
import 'features/catalog/data/folder_registry.dart';
import 'features/library/data/playlist_repository.dart';
import 'features/library/presentation/playlist_cubit.dart';
import 'app/catalog_lifecycle.dart';
import 'features/catalog/presentation/catalog_cubit.dart';
import 'features/library/data/library_repository.dart';
import 'features/library/presentation/library_cubit.dart';
import 'features/player/data/swift_audio_handler.dart';
import 'features/player/presentation/player_cubit.dart';
import 'features/player/presentation/artwork_style_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 128;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memuat koleksi musik…'),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    final support = await getApplicationSupportDirectory();
    final catalog = DeviceCatalogRepository(
      LocalAudioStore(
        Directory(p.join(support.path, 'local_music')),
        metadata: const NativeAudioMetadataReader(),
      ),
      registry: FileFolderRegistry(
        File(p.join(support.path, 'music_sources.json')),
      ),
    );
    await catalog.initialize();
    final handler = await AudioService.init<SwiftAudioHandler>(
      builder: SwiftAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.swiftmusic.app.playback',
        androidNotificationChannelName: 'Swift Music playback',
        androidNotificationOngoing: false,
        androidNotificationIcon: 'drawable/ic_stat_music_note',
        // Memungkinkan resume dari background tanpa memulai ulang foreground service.
        // Service/notifikasi bertahan saat pause; tombol Stop mengakhirinya.
        androidStopForegroundOnPause: false,
      ),
    );
    // Konfigurasikan setelah plugin audio diinisialisasi.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    handler.configureCatalog(catalog.tracks);
    await handler.restoreSession();
    final library = LibraryCubit(LocalLibraryRepository());
    final playlists = PlaylistCubit(LocalPlaylistRepository());
    await library.initialize();
    runApp(
      SwiftMusicApp(
        catalog: catalog,
        handler: handler,
        library: library,
        playlists: playlists,
        catalogCubit: CatalogCubit(
          catalog,
          importAudio: catalog.importFromDevice,
          importFolder: catalog.importFolder,
          summary: () => catalog.lastImportSummary,
          folders: () => catalog.savedFolders,
          rescan: catalog.rescanFolder,
          forget: catalog.forgetFolder,
          setAutoScan: catalog.setAutoScan,
          removeTrack: (id) async {
            await handler.removeCatalogTrack(id);
            await catalog.removeTrack(id);
          },
          onRemoved: (id) async {
            await library.removeTrack(id);
            await playlists.removeTrackEverywhere(id);
          },
          onAdded: handler.appendTracks,
        ),
      ),
    );
  } catch (error, stack) {
    debugPrint('Swift Music initialization failed: $error\n$stack');
    runApp(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Audio service gagal dimulai. Periksa konfigurasi native '
                  'pada README, lalu jalankan kembali aplikasi.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SwiftMusicApp extends StatelessWidget {
  const SwiftMusicApp({
    super.key,
    required this.catalog,
    required this.handler,
    required this.library,
    required this.playlists,
    required this.catalogCubit,
  });
  final CatalogRepository catalog;
  final SwiftAudioHandler handler;
  final LibraryCubit library;
  final PlaylistCubit playlists;
  final CatalogCubit catalogCubit;

  @override
  Widget build(
    BuildContext context,
  ) => RepositoryProvider<CatalogRepository>.value(
    value: catalog,
    child: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ArtworkStyleCubit()),
        BlocProvider<CatalogCubit>(create: (_) => catalogCubit),
        BlocProvider<LibraryCubit>(create: (_) => library),
        BlocProvider<PlaylistCubit>(create: (_) => playlists),
        BlocProvider<PlayerCubit>(create: (_) => PlayerCubit(handler)),
      ],
      child: MaterialApp(
        title: 'Swift Music',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        builder: (context, child) => MultiBlocListener(
          listeners: [
            BlocListener<PlaylistCubit, PlaylistState>(
              listenWhen: (previous, current) =>
                  current.error != null && previous.error != current.error,
              listener: (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.error!))),
            ),
            BlocListener<CatalogCubit, CatalogState>(
              listenWhen: (previous, current) =>
                  current.message != null &&
                  previous.message != current.message,
              listener: (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.message!))),
            ),
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (previous, current) =>
                  previous.error != current.error,
              listener: (context, state) {
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                if (state.error != null) {
                  messenger.showSnackBar(SnackBar(content: Text(state.error!)));
                }
              },
            ),
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (previous, current) =>
                  current.playing &&
                  current.item != null &&
                  (!previous.playing || previous.item?.id != current.item?.id),
              listener: (context, state) =>
                  context.read<LibraryCubit>().recordPlay(state.item!.id),
            ),
            BlocListener<LibraryCubit, LibraryState>(
              listenWhen: (previous, current) =>
                  current.error != null && previous.error != current.error,
              listener: (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.error!))),
            ),
          ],
          child: child ?? const SizedBox.shrink(),
        ),
        home: const CatalogLifecycle(child: MainScreen()),
      ),
    ),
  );
}
```

### lib/core/theme/app_theme.dart

```dart
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF181818);
  static const green = Color(0xFF1DB954);
  static const secondary = Color(0xFFB3B3B3);
  static const purple = Color(0xFF913BEB);
  static const pink = Color(0xFFEE278C);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: green,
      secondary: purple,
      surface: surface,
      onPrimary: Colors.black,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: green,
      thumbColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      trackHeight: 3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF24242D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
```

### lib/core/widgets/artwork.dart

```dart
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.url, this.size, this.radius = 16});
  final String url;
  final double? size;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: url.isEmpty
        ? SizedBox(
            width: size,
            height: size,
            child: const ColoredBox(
              color: Color(0xFF292339),
              child: Center(child: Icon(Icons.music_note_rounded)),
            ),
          )
        : Uri.tryParse(url)?.scheme == 'file'
        ? Image.file(
            File.fromUri(Uri.parse(url)),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(64, 1024),
            errorBuilder: (_, error, stack) => SizedBox.square(
              dimension: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Icon(Icons.album_outlined),
              ),
            ),
          )
        : CachedNetworkImage(
            memCacheWidth:
                ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(64, 1024),
            memCacheHeight:
                ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(64, 1024),
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, _) => SizedBox(
              width: size,
              height: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Center(child: Icon(Icons.music_note_rounded)),
              ),
            ),
            errorWidget: (_, _, _) => SizedBox(
              width: size,
              height: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Center(child: Icon(Icons.album_rounded)),
              ),
            ),
          ),
  );
}
```

### lib/core/widgets/brand_mark.dart

```dart
import 'package:flutter/material.dart';

/// Identitas yang sama dengan ikon launcher; decode sesuai ukuran tampil.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      'assets/branding/swift_music_icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      excludeFromSemantics: true,
    ),
  );
}
```

### lib/core/widgets/motion.dart

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 280]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Pointer feedback without competing with scrolling or the child's tap action.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    onPointerMove: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed && !MediaQuery.disableAnimationsOf(context) ? .96 : 1,
      duration: motionDuration(context, 160),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

class MotionIcon extends StatelessWidget {
  const MotionIcon(this.icon, {super.key, this.color, this.size});
  final IconData icon;
  final Color? color;
  final double? size;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motionDuration(context, 220),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: animation,
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: Icon(icon, key: ValueKey((icon, color)), color: color, size: size),
  );
}

/// Decorative playback visualizer, not FFT analysis of the audio signal.
/// A repaint-only ticker stops on pause, reduced motion, hidden routes and sleep.
class EqualizerVisualizer extends StatefulWidget {
  const EqualizerVisualizer({
    super.key,
    required this.playing,
    this.volume = 1,
    this.bars = 32,
    this.height = 38,
  });
  final bool playing;
  final double volume;
  final int bars;
  final double height;
  @override
  State<EqualizerVisualizer> createState() => _EqualizerVisualizerState();
}

class _EqualizerVisualizerState extends State<EqualizerVisualizer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _sync() {
    final active =
        widget.playing &&
        widget.volume > 0 &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (active && !_controller.isAnimating) _controller.repeat();
    if (!active) _controller.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: CustomPaint(
          painter: _BarsPainter(
            _controller,
            widget.playing && !MediaQuery.disableAnimationsOf(context),
            widget.volume,
            widget.bars,
          ),
        ),
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.clock, this.playing, this.volume, this.bars)
    : super(repaint: clock);
  final Animation<double> clock;
  final bool playing;
  final double volume;
  final int bars;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1DB954), Color(0xFFABF582)],
      ).createShader(Offset.zero & size);
    final step = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final wave =
          .22 +
          .78 *
              (math.sin(clock.value * math.pi * 2 + i * .83) *
                      math.sin(clock.value * math.pi * 4 - i * .37))
                  .abs();
      final height = playing ? 3 + (size.height - 3) * volume * wave : 3.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * step,
            (size.height - height) / 2,
            step * .58,
            height,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.playing != playing ||
      old.volume != volume ||
      old.bars != bars ||
      old.clock != clock;
}
```

### lib/core/widgets/track_tile.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/library/presentation/track_actions.dart';
import '../../features/catalog/domain/track.dart';
import '../../features/library/presentation/library_cubit.dart';
import '../../features/player/presentation/player_cubit.dart';
import '../theme/app_theme.dart';
import 'artwork.dart';
import 'motion.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track});
  final Track track;
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (before, after) => before.item?.id != after.item?.id,
    builder: (context, player) => PressScale(
      child: AnimatedContainer(
        duration: motionDuration(context),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: player.item?.id == track.id
              ? AppTheme.green.withValues(alpha: .09)
              : Colors.transparent,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            leading: Artwork(url: track.artUrl, size: 52, radius: 10),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: player.item?.id == track.id
                    ? AppTheme.green
                    : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
            ),
            trailing: BlocBuilder<LibraryCubit, LibraryState>(
              builder: (context, state) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: state.likes.contains(track.id)
                        ? 'Hapus favorit'
                        : 'Sukai lagu',
                    icon: MotionIcon(
                      state.likes.contains(track.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: state.likes.contains(track.id)
                          ? AppTheme.green
                          : AppTheme.secondary,
                    ),
                    onPressed: () =>
                        context.read<LibraryCubit>().toggleLike(track.id),
                  ),
                  IconButton(
                    tooltip: 'Menu lagu ${track.title}',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () => showTrackActions(context, track),
                  ),
                ],
              ),
            ),
            onLongPress: () => showTrackActions(context, track),
            onTap: () => context.read<PlayerCubit>().playId(track.id),
          ),
        ),
      ),
    ),
  );
}
```

### lib/app/main_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/motion.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _motion = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
  );
  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _motion.duration = motionDuration(context, 340);
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    // Tab bukan route baru: Back dari Search/Library harus kembali ke Home.
    canPop: _index == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _index != 0) {
        _select(0);
      }
    },
    child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: FadeTransition(
              opacity: _curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(_curve),
                child: IndexedStack(
                  index: _index,
                  children: [
                    TickerMode(enabled: _index == 0, child: const HomeScreen()),
                    TickerMode(
                      enabled: _index == 1,
                      child: const SearchScreen(),
                    ),
                    TickerMode(
                      enabled: _index == 2,
                      child: const LibraryScreen(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            SalomonBottomBar(
              duration: motionDuration(context, 360),
              currentIndex: _index,
              selectedItemColor: AppTheme.green,
              unselectedItemColor: AppTheme.secondary,
              onTap: _select,
              items: [
                SalomonBottomBarItem(
                  icon: const Icon(Icons.home_rounded),
                  title: const Text('Home'),
                ),
                SalomonBottomBarItem(
                  icon: const Icon(Icons.search),
                  title: const Text('Search'),
                ),
                SalomonBottomBarItem(
                  icon: const Icon(Icons.library_music_outlined),
                  title: const Text('Library'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
```

### lib/features/player/presentation/widgets/mini_player.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/widgets/artwork.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../player_cubit.dart';
import '../now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) {
      final item = state.item;
      if (item == null) return const SizedBox.shrink();
      final total = state.duration.inMilliseconds;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: PressScale(
          child: Material(
            color: const Color(0xFF2A2437),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder<void>(
                  fullscreenDialog: true,
                  transitionDuration: motionDuration(context, 380),
                  reverseTransitionDuration: motionDuration(context, 260),
                  pageBuilder: (_, animation, secondaryAnimation) =>
                      const NowPlayingScreen(),
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) =>
                          SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'player-artwork',
                          child: Artwork(
                            url: item.artUri?.toString() ?? '',
                            size: 44,
                            radius: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 20,
                          child: EqualizerVisualizer(
                            playing: state.playing,
                            volume: state.volume,
                            bars: 4,
                            height: 22,
                          ),
                        ),
                        if (state.loading)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: state.playing ? 'Pause' : 'Play',
                            onPressed: () =>
                                context.read<PlayerCubit>().togglePlay(),
                            icon: MotionIcon(
                              state.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Next',
                          onPressed: () => context.read<PlayerCubit>().next(),
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.white12,
                    value: total <= 0
                        ? 0
                        : (state.position.inMilliseconds / total)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
```

### lib/features/player/presentation/widgets/responsive_player.dart

```dart
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../../library/presentation/library_cubit.dart';
import '../artwork_style_cubit.dart';
import '../player_cubit.dart';
import 'album_stage.dart';

/// Uses safe viewport constraints rather than device names or fixed heights.
class ResponsivePlayer extends StatelessWidget {
  const ResponsivePlayer({
    super.key,
    required this.state,
    required this.lyrics,
    required this.position,
    required this.maximum,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolume,
    required this.onArtwork,
    required this.onDevices,
    required this.onQueue,
    this.onSleepTimer,
  });
  final PlayerState state;
  final String lyrics;
  final double position;
  final double maximum;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onVolume;
  final VoidCallback onArtwork;
  final VoidCallback onDevices;
  final VoidCallback onQueue;
  final VoidCallback? onSleepTimer;
  String _time(Duration duration) {
    final seconds = math.max(0, duration.inSeconds);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _header(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Tutup player',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          key: const Key('volume-trigger'),
          tooltip: 'Atur volume',
          onPressed: onVolume,
          icon: MotionIcon(
            state.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        const Expanded(
          child: Text(
            'Swift Music',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Antrean',
          onPressed: onQueue,
          icon: const Icon(Icons.queue_music),
        ),
      ],
    ),
  );
  Widget _artwork(BuildContext context, double size) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedScale(
        scale: state.playing ? 1 : .97,
        duration: motionDuration(context, 420),
        curve: Curves.easeOutCubic,
        child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
          builder: (context, selection) => Hero(
            tag: 'player-artwork',
            child: AlbumStage(
              onNext: () => context.read<ArtworkStyleCubit>().next(),
              trackId: state.item!.id,
              title: state.item!.title,
              lyrics: lyrics,
              volume: state.volume,
              url: state.item!.artUri?.toString() ?? '',
              style: selection.style,
              playing: state.playing,
              position: state.position,
              onSeek: context.read<PlayerCubit>().seek,
              size: size,
            ),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
          builder: (context, selection) => TextButton.icon(
            onPressed: onArtwork,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(
              'Tampilan album · ${selection.style.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    ],
  );
  Widget _metadata(BuildContext context, bool compact) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: state.item!.title,
              child: Text(
                state.item!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              state.item!.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppTheme.secondary),
            ),
          ],
        ),
      ),
      BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, library) => IconButton(
          tooltip: library.likes.contains(state.item!.id)
              ? 'Hapus favorit'
              : 'Sukai lagu',
          onPressed: () =>
              context.read<LibraryCubit>().toggleLike(state.item!.id),
          icon: MotionIcon(
            library.likes.contains(state.item!.id)
                ? Icons.favorite
                : Icons.favorite_border,
            color: library.likes.contains(state.item!.id)
                ? AppTheme.green
                : Colors.white,
          ),
        ),
      ),
    ],
  );
  Widget _timeline(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 40,
        child: Slider(
          key: const Key('seek-slider'),
          value: position,
          max: maximum,
          semanticFormatterCallback: (value) =>
              _time(Duration(milliseconds: value.round())),
          onChangeStart: state.duration > Duration.zero ? onSeekStart : null,
          onChanged: state.duration > Duration.zero ? onSeekChanged : null,
          onChangeEnd: state.duration > Duration.zero ? onSeekEnd : null,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _time(Duration(milliseconds: position.round())),
            style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
          ),
          Text(
            _time(state.duration),
            style: const TextStyle(fontSize: 11, color: AppTheme.secondary),
          ),
        ],
      ),
    ],
  );
  Widget _transport(BuildContext context, bool compact) {
    final player = context.read<PlayerCubit>();
    return SizedBox(
      key: const Key('transport-controls'),
      height: compact ? 60 : 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            child: IconButton(
              tooltip: 'Shuffle',
              onPressed: player.toggleShuffle,
              icon: MotionIcon(
                Icons.shuffle,
                color: state.shuffle ? AppTheme.green : AppTheme.secondary,
              ),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Previous',
              onPressed: player.previous,
              icon: const Icon(Icons.skip_previous_rounded, size: 30),
            ),
          ),
          SizedBox.square(
            dimension: compact ? 60 : 72,
            child: PressScale(
              child: FilledButton(
                key: const Key('main-play-button'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                onPressed: state.loading ? null : player.togglePlay,
                child: state.loading
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : MotionIcon(
                        state.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
              ),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Next',
              onPressed: player.next,
              icon: const Icon(Icons.skip_next_rounded, size: 30),
            ),
          ),
          Flexible(
            child: IconButton(
              tooltip: 'Repeat: ${state.repeat.name}',
              onPressed: player.cycleRepeat,
              icon: MotionIcon(
                state.repeat == AudioServiceRepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: state.repeat == AudioServiceRepeatMode.none
                    ? AppTheme.secondary
                    : AppTheme.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _devices() => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onDevices,
              icon: const Icon(Icons.devices, size: 18),
              label: const Text(
                'This device · Demo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sleep timer',
          onPressed: onSleepTimer,
          icon: Icon(
            state.sleepActive ? Icons.bedtime : Icons.bedtime_outlined,
            color: state.sleepActive ? AppTheme.green : AppTheme.secondary,
          ),
        ),
      ],
    ),
  );
  List<Widget> _controls(BuildContext context, bool compact) => [
    _metadata(context, compact),
    const SizedBox(height: 6),
    EqualizerVisualizer(
      playing: state.playing,
      volume: state.volume,
      height: compact ? 20 : 28,
    ),
    _timeline(context),
    const SizedBox(height: 8),
    _transport(context, compact),
    const SizedBox(height: 6),
    _devices(),
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final wide =
          viewport.maxWidth >= 760 ||
          (viewport.maxWidth >= 480 && viewport.maxWidth > viewport.maxHeight);
      final compact = viewport.maxHeight < 760;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final horizontal = viewport.maxWidth < 360 ? 16.0 : 24.0;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
            child: LayoutBuilder(
              builder: (context, available) {
                if (wide) {
                  final stageSize = math.max(
                    128.0,
                    math.min(
                      420.0,
                      math.min(
                        (available.maxWidth - 24) * .46,
                        available.maxHeight - 100,
                      ),
                    ),
                  );
                  return Column(
                    children: [
                      _header(context),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Center(
                                  child: _artwork(context, stageSize),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, panel) =>
                                    SingleChildScrollView(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: panel.maxHeight,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: _controls(context, true),
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                // Large accessibility text gets a scroll fallback instead of clipping.
                final reserved =
                    (compact ? 360.0 : 380.0) + math.max(0, scale - 1) * 150;
                // Accessibility text needs room for the lyric header and body.
                // Let the page scroll rather than shrinking lyrics out of view.
                final minimumStage = scale > 1.3 ? available.maxWidth : 128.0;
                final stageSize = math.min(
                  400.0,
                  math.min(
                    available.maxWidth,
                    math.max(minimumStage, available.maxHeight - reserved),
                  ),
                );
                return SingleChildScrollView(
                  key: const Key('player-scroll'),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: available.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _header(context),
                        const SizedBox(height: 8),
                        _artwork(context, stageSize),
                        const SizedBox(height: 8),
                        ..._controls(context, compact),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
```

### lib/features/player/presentation/widgets/album_stage.dart

```dart
import 'package:flutter/material.dart';
import '../../../../core/widgets/motion.dart';
import '../artwork_style_cubit.dart';
import 'album_display.dart';
import 'lyrics_panel.dart';

class AlbumStage extends StatelessWidget {
  const AlbumStage({
    super.key,
    required this.style,
    required this.size,
    required this.trackId,
    required this.title,
    required this.url,
    required this.lyrics,
    required this.playing,
    required this.volume,
    required this.onNext,
    this.position = Duration.zero,
    this.onSeek,
  });
  final ArtworkStyle style;
  final double size;
  final String trackId;
  final String title;
  final String url;
  final String lyrics;
  final bool playing;
  final double volume;
  final VoidCallback onNext;
  final Duration position;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Ganti tampilan album',
    hint: 'Ketuk untuk tampilan berikutnya. Sekarang ${style.label}',
    onTap: onNext,
    child: GestureDetector(
      key: const Key('album-stage'),
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: onNext,
      child: SizedBox.square(
        dimension: size,
        child: AnimatedSwitcher(
          duration: motionDuration(context, 420),
          reverseDuration: motionDuration(context, 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .94, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: TickerMode(
            key: ValueKey((style, trackId)),
            enabled: TickerMode.valuesOf(context).enabled,
            child: SizedBox.square(
              dimension: size,
              child: style == ArtworkStyle.lyrics
                  ? LyricsPanel(
                      trackId: trackId,
                      title: title,
                      fallback: lyrics,
                      position: position,
                      onSeek: onSeek,
                    )
                  : AlbumDisplay(
                      url: url,
                      size: size,
                      style: style,
                      playing: playing,
                      volume: volume,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
```

### lib/features/player/presentation/widgets/lyrics_panel.dart

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/lrc_document.dart';

/// Plain text lyrics supplied by the catalog or user; no fabricated timing.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.trackId,
    required this.title,
    required this.fallback,
    this.load,
    this.save,
    this.position = Duration.zero,
    this.onSeek,
  });
  final String trackId;
  final String title;
  final String fallback;
  final Future<String?> Function(String)? load;
  final Future<void> Function(String, String)? save;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  String? _custom;
  int _revision = 0;
  bool _saving = false;
  final _scroll = ScrollController();
  String? _parsedText;
  LrcDocument _document = LrcDocument.parse('');
  int _lastActive = -2;
  DateTime _manualUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String get _key => 'lyrics_${widget.trackId}';
  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _custom = null;
      _revision++;
      _lastActive = -2;
      _restore();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _importLrc() async {
    final id = widget.trackId;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Pilih lirik LRC atau TXT',
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );
      if (file == null || !mounted || widget.trackId != id) return;
      final bytes = <int>[];
      await for (final chunk in file.readAsByteStream()) {
        if (bytes.length + chunk.length > 256 * 1024) {
          throw const FormatException(
            'File lirik terlalu besar (maksimal 256 KiB).',
          );
        }
        bytes.addAll(chunk);
      }
      String text;
      if (bytes.length >= 2 &&
          ((bytes[0] == 255 && bytes[1] == 254) ||
              (bytes[0] == 254 && bytes[1] == 255))) {
        final little = bytes[0] == 255;
        text = String.fromCharCodes([
          for (var i = 2; i + 1 < bytes.length; i += 2)
            little
                ? bytes[i] | bytes[i + 1] << 8
                : bytes[i] << 8 | bytes[i + 1],
        ]);
      } else {
        text = utf8.decode(bytes);
      }
      if (text.length > 100000) {
        throw const FormatException('Teks lirik terlalu panjang.');
      }
      if (mounted && widget.trackId == id) await _store(text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lirik gagal diimpor. Gunakan TXT/LRC UTF-8 atau UTF-16 maksimal 256 KiB.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _store(String result) async {
    final revision = ++_revision;
    final id = widget.trackId;
    final key = _key;
    setState(() => _saving = true);
    try {
      if (widget.save != null) {
        await widget.save!(id, result);
      } else {
        await SharedPreferencesAsync().setString(key, result);
      }
      if (mounted && revision == _revision) {
        setState(() {
          _custom = result;
          _lastActive = -2;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lirik belum berhasil disimpan. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final value =
          await (widget.load?.call(widget.trackId) ??
              SharedPreferencesAsync().getString(_key));
      if (mounted && revision == _revision) setState(() => _custom = value);
    } catch (_) {
      /* Lirik katalog tetap dapat dibaca tanpa preferensi. */
    }
  }

  Future<void> _edit() async {
    final trackId = widget.trackId;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _LyricsEditor(initial: _custom ?? ''),
    );
    if (result == null || !mounted || widget.trackId != trackId) return;
    await _store(result);
  }

  @override
  Widget build(BuildContext context) {
    final text = (_custom?.trim().isNotEmpty ?? false)
        ? _custom!
        : widget.fallback;
    if (_parsedText != text) {
      _parsedText = text;
      _document = LrcDocument.parse(text);
      _lastActive = -2;
    }
    final active = _document.activeIndex(widget.position);
    final extent = 84.0 * MediaQuery.textScalerOf(context).scale(1);
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scroll.hasClients ||
            active < 0 ||
            DateTime.now().isBefore(_manualUntil)) {
          return;
        }
        final target = (active * extent - extent / 2).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
        } else {
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF462B69), Color(0xFF17132A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Lirik',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Impor lirik LRC',
                onPressed: _saving ? null : _importLrc,
                icon: const Icon(Icons.file_open_outlined, size: 22),
              ),
              IconButton(
                tooltip: 'Tambah atau edit lirik',
                onPressed: _saving ? null : _edit,
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.green,
                ),
              ),
            ],
          ),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _document.synced
                ? NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction != ScrollDirection.idle) {
                        _manualUntil = DateTime.now().add(
                          const Duration(seconds: 4),
                        );
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: extent,
                      itemCount: _document.lines.length,
                      itemBuilder: (context, index) => GestureDetector(
                        onLongPress: widget.onSeek == null
                            ? null
                            : () => widget.onSeek!(_document.lines[index].time),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedDefaultTextStyle(
                            duration: motionDuration(context, 250),
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: index == active
                                  ? AppTheme.green
                                  : AppTheme.secondary,
                            ),
                            child: Text(
                              _document.lines[index].text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      key: ValueKey(widget.trackId),
                      child: Text(
                        text.trim().isEmpty
                            ? 'Lirik belum tersedia. Ketuk ikon pensil untuk menambahkan lirik.'
                            : text,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.65,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LyricsEditor extends StatefulWidget {
  const _LyricsEditor({required this.initial});
  final String initial;
  @override
  State<_LyricsEditor> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends State<_LyricsEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lirik lagu'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          minLines: 5,
          maxLines: 10,
          maxLength: 100000,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Tempel atau tulis lirik lagu ini',
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}
```

### lib/features/player/presentation/widgets/neon_visualizer.dart

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Stylized motion, not FFT data. The owner stops the clock when hidden/paused.
class NeonVisualizer extends StatelessWidget {
  const NeonVisualizer({
    super.key,
    required this.clock,
    required this.circular,
    required this.volume,
    required this.active,
    required this.size,
  });
  final Animation<double> clock;
  final bool circular;
  final double volume;
  final bool active;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: ColoredBox(
      color: const Color(0xFF10071F),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _NeonPainter(clock, circular, volume, active),
              ),
            ),
            if (circular)
              SizedBox(
                width: size * .4,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SWIFT\nMUSIC',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NeonPainter extends CustomPainter {
  _NeonPainter(this.clock, this.circular, this.volume, this.active)
    : super(repaint: clock);
  final Animation<double> clock;
  final bool circular;
  final double volume;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    // The owner freezes the clock on pause: geometry stays at its last phase.
    final phase = clock.value * math.pi * 2;
    final gain = volume;
    final bounds = Offset.zero & size;
    final colors = [
      const Color(0xFF19E7ED),
      const Color(0xFF775BFF),
      const Color(0xFFFF359F),
    ];
    if (circular) {
      final center = size.center(Offset.zero);
      final radius = size.width * .29;
      final shader = SweepGradient(
        colors: [...colors, colors.first],
        transform: GradientRotation(phase),
      ).createShader(bounds);
      final paint = Paint()
        ..shader = shader
        ..strokeWidth = size.width * .008
        ..strokeCap = StrokeCap.round;
      final glow = Paint()
        ..shader = shader
        ..strokeWidth = size.width * .02
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      final bars = Path();
      for (var i = 0; i < 72; i++) {
        final angle = i / 72 * math.pi * 2;
        final envelope =
            .25 +
            .75 *
                (math.sin(angle * 5 + phase) * math.cos(angle * 3 - phase))
                    .abs();
        final length = size.width * (.015 + .13 * gain * envelope);
        final direction = Offset(math.cos(angle), math.sin(angle));
        final start = center + direction * radius;
        final end = center + direction * (radius + length);
        bars.moveTo(start.dx, start.dy);
        bars.lineTo(end.dx, end.dy);
      }
      // One glow pass for the whole ring rather than a blur per bar.
      canvas.drawPath(bars, glow);
      canvas.drawPath(bars, paint);
      canvas.drawCircle(
        center,
        radius - 8,
        Paint()
          ..color = colors.first.withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      _ribbons(canvas, size, phase, gain, colors);
    }
  }

  void _ribbons(
    Canvas canvas,
    Size size,
    double phase,
    double gain,
    List<Color> colors,
  ) {
    final shader = LinearGradient(
      colors: colors,
    ).createShader(Offset.zero & size);
    final baseline = size.height * .53;
    for (var layer = 0; layer < 3; layer++) {
      final upper = <Offset>[];
      final lower = <Offset>[];
      for (var i = 0; i <= 96; i++) {
        final t = i / 96;
        final envelope = math.sin(math.pi * t);
        final wave =
            math.sin(t * math.pi * 4 - phase + layer * .85) * .7 +
            math.sin(t * math.pi * 2 + phase + layer * .55) * .3;
        final amplitude =
            envelope * size.height * (.025 + .21 * gain) * (1 - layer * .16);
        final x = size.width * (.07 + .86 * t);
        upper.add(
          Offset(x, baseline + wave * amplitude - envelope * amplitude * .35),
        );
        lower.add(
          Offset(x, baseline + wave * amplitude + envelope * amplitude * .35),
        );
      }
      final ribbon = Path()..moveTo(upper.first.dx, upper.first.dy);
      for (final point in upper.skip(1)) {
        ribbon.lineTo(point.dx, point.dy);
      }
      for (final point in lower.reversed) {
        ribbon.lineTo(point.dx, point.dy);
      }
      ribbon.close();
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = shader
          ..color = Colors.white.withValues(alpha: .15 + layer * .055),
      );
      final edge = Path()..moveTo(upper.first.dx, upper.first.dy);
      for (final point in upper.skip(1)) {
        edge.lineTo(point.dx, point.dy);
      }
      if (layer == 1) {
        canvas.drawPath(
          edge,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawPath(
        edge,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: .75),
      );
    }
  }

  @override
  bool shouldRepaint(_NeonPainter old) =>
      old.circular != circular ||
      old.volume != volume ||
      old.active != active ||
      old.clock != clock;
}
```

### lib/features/player/presentation/widgets/album_display.dart

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/artwork.dart';
import '../artwork_style_cubit.dart';
import 'neon_visualizer.dart';

/// Animation is visual only: it never seeks, restarts or alters the audio.
class AlbumDisplay extends StatefulWidget {
  const AlbumDisplay({
    super.key,
    required this.url,
    required this.size,
    required this.style,
    required this.playing,
    this.volume = 1,
  });
  final String url;
  final double size;
  final ArtworkStyle style;
  final bool playing;
  final double volume;
  @override
  State<AlbumDisplay> createState() => _AlbumDisplayState();
}

class _AlbumDisplayState extends State<AlbumDisplay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _neon = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _sync() {
    final active =
        widget.playing &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (active && widget.style == ArtworkStyle.vinyl) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
    if (active && widget.style == ArtworkStyle.pulse) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
    if (active &&
        widget.volume > 0 &&
        (widget.style == ArtworkStyle.spectrum ||
            widget.style == ArtworkStyle.wave)) {
      if (!_neon.isAnimating) _neon.repeat();
    } else {
      _neon.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AlbumDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    _pulse.dispose();
    _neon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Tampilan album ${widget.style.label}',
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: switch (widget.style) {
            ArtworkStyle.lyrics => const SizedBox.shrink(),
            ArtworkStyle.spectrum || ArtworkStyle.wave => NeonVisualizer(
              clock: _neon,
              circular: widget.style == ArtworkStyle.spectrum,
              volume: widget.volume,
              active: widget.playing && !reduced,
              size: widget.size,
            ),
            ArtworkStyle.cover => Artwork(
              url: widget.url,
              size: widget.size,
              radius: 28,
            ),
            ArtworkStyle.vinyl => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RotationTransition(
                    turns: reduced
                        ? const AlwaysStoppedAnimation(0)
                        : _rotation,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _VinylPainter()),
                        ),
                        Container(
                          width: widget.size * .44,
                          height: widget.size * .44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.green.withValues(alpha: .65),
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: Artwork(
                              url: widget.url,
                              size: widget.size * .44,
                              radius: widget.size,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 2),
                  ),
                ),
              ],
            ),
            ArtworkStyle.pulse => AnimatedBuilder(
              animation: _pulse,
              child: Artwork(url: widget.url, size: widget.size, radius: 28),
              builder: (context, child) {
                final value = reduced || !widget.playing
                    ? 0.0
                    : Curves.easeInOut.transform(_pulse.value);
                return Transform.scale(
                  scale: .96 + .04 * value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.purple.withValues(
                            alpha: .18 + .2 * value,
                          ),
                          blurRadius: 20 + 25 * value,
                          spreadRadius: 2 + 5 * value,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              },
            ),
          },
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xFF333338),
            Color(0xFF09090D),
            Color(0xFF24242A),
            Color(0xFF08080B),
          ],
          stops: [0, .3, .8, 1],
        ).createShader(Offset.zero & size),
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .09);
    for (var ring = .26; ring < .98; ring += .025) {
      canvas.drawCircle(center, radius * ring, groove);
    }
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * .045
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .13);
    for (final angle in [-math.pi / 3, math.pi * .65]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * .78),
        angle,
        .48,
        false,
        shine,
      );
    }
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}
```

### lib/features/player/presentation/widgets/volume_control.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../player_cubit.dart';

/// A floating vertical panel; it never takes space in the player layout.
class VolumeControl extends StatelessWidget {
  const VolumeControl({
    super.key,
    required this.height,
    required this.onClose,
    required this.onInteraction,
    required this.onHold,
    required this.onRelease,
  });
  final double height;
  final VoidCallback onClose;
  final VoidCallback onInteraction;
  final VoidCallback onHold;
  final VoidCallback onRelease;
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (before, after) => before.volume != after.volume,
    builder: (context, state) {
      final player = context.read<PlayerCubit>();
      void action(VoidCallback callback) {
        onInteraction();
        callback();
      }

      return Listener(
        onPointerDown: (_) => onHold(),
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: SizedBox(
          key: const Key('volume-overlay'),
          width: 80,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  elevation: 16,
                  color: const Color(0xFF24232D),
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          '${(state.volume * 100).round()}%',
                          style: const TextStyle(
                            color: AppTheme.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Volume naik',
                          onPressed: () =>
                              action(() => player.adjustVolume(.05)),
                          icon: const Icon(Icons.add_rounded),
                        ),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              key: const Key('volume-slider'),
                              value: state.volume,
                              semanticFormatterCallback: (value) =>
                                  'Volume aplikasi ${(value * 100).round()} persen',
                              onChanged: (value) =>
                                  action(() => player.setVolume(value)),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Volume turun',
                          onPressed: () =>
                              action(() => player.adjustVolume(-.05)),
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: IconButton(
                                tooltip: state.volume == 0
                                    ? 'Aktifkan suara'
                                    : 'Bisukan',
                                onPressed: () => action(player.toggleMute),
                                icon: MotionIcon(
                                  state.volume == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: AppTheme.green,
                                ),
                              ),
                            ),
                            Expanded(
                              child: IconButton(
                                tooltip: 'Tutup volume',
                                onPressed: onClose,
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                          ],
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
    },
  );
}
```

### lib/features/player/presentation/now_playing_screen.dart

```dart
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import 'artwork_style_cubit.dart';
import 'widgets/responsive_player.dart';
import '../../../core/widgets/motion.dart';
import 'widgets/volume_control.dart';
import 'widgets/sleep_timer_sheet.dart';
import '../../catalog/domain/catalog_repository.dart';
import 'player_cubit.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showVolume = false;
  Timer? _volumeTimer;
  bool _volumeHeld = false;
  void _scheduleVolumeHide() {
    _volumeTimer?.cancel();
    if (!_showVolume || _volumeHeld) return;
    _volumeTimer = Timer(const Duration(seconds: 3), _hideVolume);
  }

  void _hideVolume() {
    _volumeTimer?.cancel();
    _volumeHeld = false;
    if (mounted && _showVolume) setState(() => _showVolume = false);
  }

  void _toggleVolume() {
    setState(() => _showVolume = !_showVolume);
    if (_showVolume) {
      _scheduleVolumeHide();
    } else {
      _volumeTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    super.dispose();
  }

  double? _dragPosition;
  String? _dragTrack;
  void _chooseArtwork() {
    final preference = context.read<ArtworkStyleCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
            bloc: preference,
            builder: (context, selection) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Tampilan album',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final style in ArtworkStyle.values)
                  ListTile(
                    enabled: !selection.saving,
                    selected: selection.style == style,
                    leading: Icon(switch (style) {
                      ArtworkStyle.cover => Icons.image_outlined,
                      ArtworkStyle.lyrics => Icons.lyrics_outlined,
                      ArtworkStyle.vinyl => Icons.album_rounded,
                      ArtworkStyle.spectrum => Icons.radar_rounded,
                      ArtworkStyle.wave => Icons.waves_rounded,
                      ArtworkStyle.pulse => Icons.blur_on_rounded,
                    }),
                    title: Text(style.label),
                    subtitle: Text(style.description),
                    trailing: selection.style == style
                        ? const Icon(Icons.check_circle, color: AppTheme.green)
                        : null,
                    onTap: () async {
                      await preference.select(style);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted && preference.state.error != null) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text(preference.state.error!)),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _devices() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect to a device',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Simulasi UI · audio tetap diputar di perangkat ini.',
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const ListTile(
                  leading: Icon(Icons.smartphone, color: AppTheme.green),
                  title: Text('This device'),
                  subtitle: Text('Sedang digunakan'),
                  trailing: Icon(Icons.check, color: AppTheme.green),
                ),
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.speaker_group_outlined),
                  title: Text('Living room speaker'),
                  subtitle: Text('Demo · tidak tersambung'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) {
      final item = state.item;
      if (item == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Pilih lagu.')),
        );
      }
      final cubit = context.read<PlayerCubit>();
      final maximum = math.max(1.0, state.duration.inMilliseconds.toDouble());
      final position =
          ((_dragTrack == item.id ? _dragPosition : null) ??
                  state.position.inMilliseconds.toDouble())
              .clamp(0.0, maximum)
              .toDouble();
      final tracks = context.read<CatalogRepository>().tracks.where(
        (track) => track.id == item.id,
      );
      final lyrics = tracks.isEmpty
          ? 'Lirik belum tersedia.'
          : tracks.first.lyrics;
      return PopScope<Object?>(
        canPop: !_showVolume,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _hideVolume();
        },
        child: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF482644),
                  Color(0xFF20192D),
                  AppTheme.background,
                ],
                stops: [0, .42, 1],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => Stack(
                  children: [
                    Positioned.fill(
                      child: ResponsivePlayer(
                        state: state,
                        lyrics: lyrics,
                        position: position,
                        maximum: maximum,
                        onVolume: _toggleVolume,
                        onArtwork: _chooseArtwork,
                        onDevices: _devices,
                        onQueue: () => _queue(context),
                        onSleepTimer: () => showSleepTimer(context),
                        onSeekStart: (value) => setState(() {
                          _dragTrack = item.id;
                          _dragPosition = value;
                        }),
                        onSeekChanged: (value) =>
                            setState(() => _dragPosition = value),
                        onSeekEnd: (value) {
                          if (_dragTrack == item.id) {
                            cubit.seek(Duration(milliseconds: value.round()));
                          }
                          setState(() {
                            _dragTrack = null;
                            _dragPosition = null;
                          });
                        },
                      ),
                    ),
                    if (_showVolume)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const Key('volume-dismiss-area'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _hideVolume,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: IgnorePointer(
                          ignoring: !_showVolume,
                          child: AnimatedSwitcher(
                            duration: motionDuration(context, 220),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin: const Offset(-.3, 0),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    child: child,
                                  ),
                                ),
                            child: !_showVolume
                                ? const SizedBox.shrink()
                                : VolumeControl(
                                    key: const Key('floating-volume'),
                                    height: math.min(
                                      320.0,
                                      math.max(200.0, viewport.maxHeight - 32),
                                    ),
                                    onClose: _hideVolume,
                                    onInteraction: _scheduleVolumeHide,
                                    onHold: () {
                                      _volumeHeld = true;
                                      _volumeTimer?.cancel();
                                    },
                                    onRelease: () {
                                      _volumeHeld = false;
                                      _scheduleVolumeHide();
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  void _queue(BuildContext context) {
    final player = context.read<PlayerCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: BlocBuilder<PlayerCubit, PlayerState>(
            bloc: player,
            buildWhen: (a, b) =>
                a.queueItems != b.queueItems || a.item?.id != b.item?.id,
            builder: (context, state) => Column(
              children: [
                const ListTile(
                  title: Text(
                    'Antrean pemutaran',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Tahan dan geser untuk mengubah urutan'),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: state.queueItems.length,
                    onReorderItem: (from, to) {
                      player.moveQueue(from, to);
                    },
                    itemBuilder: (context, index) {
                      final item = state.queueItems[index];
                      return ListTile(
                        key: ValueKey(item.id),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: item.id == state.item?.id
                                ? AppTheme.green
                                : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          item.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Keluarkan dari antrean',
                          icon: const Icon(Icons.close),
                          onPressed: () => player.removeQueue(item),
                        ),
                        onTap: () => player.playId(item.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### lib/features/home/presentation/home_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../library/presentation/library_cubit.dart';
import '../../player/presentation/player_cubit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  String get _greeting {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good Morning'
        : hour < 18
        ? 'Good Afternoon'
        : 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CatalogCubit>();
    final tracks = context.read<CatalogRepository>().tracks;
    void play(Track track) => context.read<PlayerCubit>().playId(track.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            const BrandMark(size: 30),
            const SizedBox(width: 8),
            const Text(
              'SWIFT MUSIC',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppTheme.purple, AppTheme.pink],
                ),
              ),
              child: const Icon(Icons.headphones, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          _greeting,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const Text(
          'Your next favorite is waiting.',
          style: TextStyle(color: AppTheme.secondary),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF54218A), Color(0xFFB62D83), Color(0xFF21192F)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THE DAILY ESCAPE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Find your\nfrequency.',
                      style: TextStyle(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => play(tracks.first),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Listen now'),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.album_outlined, size: 76, color: Colors.white54),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _Heading('Recently Played'),
        BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            // Isi shortcut awal dengan katalog sampai ada riwayat pemutaran nyata.
            final ordered = [
              ...state.recent
                  .map((id) => tracks.where((t) => t.id == id))
                  .expand((t) => t),
              ...tracks.where((t) => !state.recent.contains(t.id)),
            ].take(6).toList();
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ordered.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent:
                    64 *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                      1,
                      3,
                    ),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) => PressScale(
                child: Material(
                  color: const Color(0xFF232229),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => play(ordered[i]),
                    child: Row(
                      children: [
                        Artwork(url: ordered[i].artUrl, size: 56, radius: 8),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ordered[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        const _Heading('Made For You'),
        _TrackShelf(tracks: tracks.take(3).toList(), onPlay: play),
        const SizedBox(height: 28),
        const _Heading('Top Recommendations'),
        _TrackShelf(tracks: tracks.reversed.toList(), onPlay: play),
        const SizedBox(height: 12),
        const Text(
          'Demo picks · recommendations are curated, not personalized yet.',
          style: TextStyle(color: AppTheme.secondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(width: 3, height: 20, color: AppTheme.pink),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ],
    ),
  );
}

class _TrackShelf extends StatelessWidget {
  const _TrackShelf({required this.tracks, required this.onPlay});
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180 + MediaQuery.textScalerOf(context).scale(14) * 3,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, i) => SizedBox(
        width: 148,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onPlay(tracks[i]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Artwork(url: tracks[i].artUrl, size: 148, radius: 20),
                const SizedBox(height: 10),
                Text(
                  tracks[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  tracks[i].genre,
                  style: const TextStyle(color: AppTheme.secondary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
```

### lib/features/search/presentation/search_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/track_tile.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../catalog/domain/music_filter.dart';
import 'search_filters.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String? _genre;
  MusicFilter _filter = const MusicFilter();
  static const _colors = [
    Color(0xFF8C239B),
    Color(0xFF176A60),
    Color(0xFFAD354F),
    Color(0xFF6841A8),
    Color(0xFF9A5D21),
    Color(0xFF2852A0),
  ];
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CatalogCubit>().state;
    final catalog = context.read<CatalogRepository>();
    final folder = state.sources
        .where((source) => source.id == _filter.folder)
        .firstOrNull;
    final folderTracks = folder?.fingerprints.values
        .map((value) => value.split('|').last)
        .toSet();
    final results = catalog
        .search(_controller.text, genre: _genre)
        .where((track) => _filter.matches(track, folderTracks: folderTracks))
        .toList();
    final genres = catalog.tracks.map((t) => t.genre).toSet().toList();
    final filtering =
        _controller.text.trim().isNotEmpty || _genre != null || _filter.active;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Discover',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Judul lagu atau artis',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: () => setState(_controller.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        SearchFilters(
          filter: _filter,
          tracks: state.tracks,
          folders: state.sources,
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        const SizedBox(height: 16),
        if (_genre != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(_genre!),
              onDeleted: () => setState(() => _genre = null),
            ),
          ),
        AnimatedSwitcher(
          duration: motionDuration(context),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            filtering ? 'Search results' : 'Browse all',
            key: ValueKey(filtering),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),
        if (!filtering)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: genres.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: ((MediaQuery.sizeOf(context).width - 40) / 180)
                  .floor()
                  .clamp(2, 4),
              mainAxisExtent:
                  140 * MediaQuery.textScalerOf(context).scale(14) / 14,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (_, i) => PressScale(
              child: Material(
                color: _colors[i % _colors.length],
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _genre = genres[i]),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          genres[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        const Spacer(),
                        const Align(
                          alignment: Alignment.bottomRight,
                          child: Icon(
                            Icons.graphic_eq,
                            color: Colors.white54,
                            size: 32,
                          ),
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
    // Build result rows on demand rather than retaining the whole collection.
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 1 + (filtering ? (results.isEmpty ? 1 : results.length) : 0),
      itemBuilder: (context, index) {
        if (index == 0) return header;
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Tidak ada lagu yang cocok.'),
          );
        }
        return TrackTile(track: results[index - 1]);
      },
    );
  }
}
```

### lib/features/library/presentation/library_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/track_tile.dart';
import '../../catalog/data/local_audio_store.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../about/presentation/about_screen.dart';
import 'library_cubit.dart';
import 'playlist_cubit.dart';
import 'library_sections.dart';
import 'collection_screens.dart';
import 'track_actions.dart';
import 'backup_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  void _importMenu(BuildContext context) {
    final catalog = context.read<CatalogCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Cadangkan / pulihkan koleksi'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Buat playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final id = await createPlaylist(context);
                if (id != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistScreen(id: id),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Folder musik'),
              subtitle: const Text('Termasuk musik di dalam subfolder'),
              onTap: () {
                Navigator.pop(sheetContext);
                catalog.importFromFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('File audio'),
              onTap: () {
                Navigator.pop(sheetContext);
                catalog.importFromDevice();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your Library',
                    maxLines: 2,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Tentang Swift Music',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline),
                ),
                IconButton(
                  tooltip: 'Impor lagu dari perangkat',
                  onPressed: catalog.importing
                      ? null
                      : () => _importMenu(context),
                  icon: const Icon(Icons.file_upload_outlined),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: MediaQuery.textScalerOf(context).scale(14) > 18,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Artists'),
              Tab(text: 'Albums'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _LocalCollection(),
                _GroupList(byArtist: true),
                _GroupList(byArtist: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalCollection extends StatelessWidget {
  const _LocalCollection();
  void _formats(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format musik',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text('File yang dapat dipilih untuk dicoba diputar:'),
            Wrap(
              spacing: 8,
              children: LocalAudioStore.extensions
                  .map((ext) => Chip(label: Text(ext.toUpperCase())))
                  .toList(),
            ),
            const Text(
              'Kemampuan putar bergantung pada codec dan perangkat. MP3, AAC/M4A dan WAV adalah pilihan umum. '
              'WMA, APE, DSD, MIDI dan file berproteksi DRM belum didukung. Mengganti ekstensi tidak mengubah format audio.',
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    final collections = context.watch<PlaylistCubit>();
    final local = collections.sorted(
      catalog.tracks.where((track) => track.isLocal),
    );
    final library = context.watch<LibraryCubit>().state;
    final liked = catalog.tracks
        .where((track) => library.likes.contains(track.id))
        .toList();
    return CustomScrollView(
      key: const ValueKey('library-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Lagu di perangkat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pilih folder beserta subfolder, atau beberapa file audio.',
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: catalog.importing
                      ? null
                      : () => context.read<CatalogCubit>().importFromFolder(),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Pilih folder musik'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: catalog.importing
                      ? null
                      : () => context.read<CatalogCubit>().importFromDevice(),
                  icon: const Icon(Icons.audio_file_outlined),
                  label: const Text('Pilih lagu lokal'),
                ),
                if (catalog.importing) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: catalog.total > 0
                        ? catalog.completed / catalog.total
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    catalog.total > 0
                        ? '${catalog.completed}/${catalog.total} · ${catalog.folder}'
                        : 'Memindai ${catalog.folder ?? 'pilihan musik'}…',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton(
                    onPressed: catalog.cancelling
                        ? null
                        : () => context.read<CatalogCubit>().cancelImport(),
                    child: Text(
                      catalog.cancelling ? 'Menghentikan…' : 'Hentikan impor',
                    ),
                  ),
                ],
                TextButton.icon(
                  onPressed: () => _formats(context),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Lihat format musik'),
                ),
                const Text(
                  'Lagu disalin ke penyimpanan aplikasi agar tetap tersedia secara offline.',
                  style: TextStyle(color: AppTheme.secondary, fontSize: 11),
                ),
                if (local.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Belum ada lagu lokal. Pilih folder atau file musik Anda.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (catalog.sources.isNotEmpty)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Folder tersimpan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: catalog.sources.length,
            itemBuilder: (_, i) => SavedFolderCard(folder: catalog.sources[i]),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: PlaylistsHeading()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: collections.state.playlists.length,
            itemBuilder: (_, i) =>
                UserPlaylistCard(playlist: collections.state.playlists[i]),
          ),
        ),
        if (collections.state.playlists.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Buat playlist untuk mengatur koleksi Anda.',
                style: TextStyle(color: AppTheme.secondary),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Material(
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackCollectionScreen(
                      title: 'Liked Songs',
                      liked: true,
                    ),
                  ),
                ),
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF403078), Color(0xFF213F37)],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.favorite,
                        color: AppTheme.green,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Liked Songs',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text('${liked.length} lagu'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Semua lagu lokal (${local.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const LibrarySortButton(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.builder(
            itemCount: local.length,
            itemBuilder: (_, index) => TrackTile(track: local[index]),
          ),
        ),
      ],
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.byArtist});
  final bool byArtist;
  @override
  Widget build(BuildContext context) {
    final tracks = context.watch<CatalogCubit>().state.tracks;
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      (groups[byArtist ? track.artist : track.album] ??= []).add(track);
    }
    final entries = groups.entries.toList();
    return ListView.builder(
      key: ValueKey(byArtist ? 'artist-groups' : 'album-groups'),
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(byArtist ? Icons.person_outline : Icons.album_outlined),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} songs'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TrackCollectionScreen(
                title: entry.key,
                artist: byArtist ? entry.key : null,
                album: byArtist ? null : entry.key,
              ),
            ),
          ),
        );
      },
    );
  }
}
```

### lib/features/about/presentation/about_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Baca versi paket terpasang agar mengikuti pubspec dan build override.
  final Future<PackageInfo> _package = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tentang Swift Music')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Center(child: BrandMark(size: 96)),
                const SizedBox(height: 20),
                const Text(
                  'Swift Music',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Musik favorit, selalu dekat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Versi aplikasi',
                          style: TextStyle(color: AppTheme.secondary),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<PackageInfo>(
                          future: _package,
                          builder: (context, snapshot) {
                            final info = snapshot.data;
                            if (info != null) {
                              return Text(
                                '${info.version} (build ${info.buildNumber})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }
                            return Text(
                              snapshot.hasError
                                  ? 'Versi tidak tersedia'
                                  : 'Memuat versi…',
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Developer',
                          style: TextStyle(color: AppTheme.secondary),
                        ),
                        const SizedBox(height: 8),
                        const SelectableText(
                          'ekoardianto.pro@gmail.com',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
```

### lib/app/catalog_lifecycle.dart

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/catalog/presentation/catalog_cubit.dart';

class CatalogLifecycle extends StatefulWidget {
  const CatalogLifecycle({super.key, required this.child});
  final Widget child;
  @override
  State<CatalogLifecycle> createState() => _CatalogLifecycleState();
}

class _CatalogLifecycleState extends State<CatalogLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resume();
    });
  }

  void _resume() {
    _timer?.cancel();
    context.read<CatalogCubit>().checkSavedFolders();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) context.read<CatalogCubit>().checkSavedFolders();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

### lib/features/library/presentation/collection_screens.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/track_tile.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../domain/music_playlist.dart';
import 'playlist_cubit.dart';
import 'library_cubit.dart';
import 'track_actions.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistCubit>();
    final playlist = playlists.state.playlists
        .where((list) => list.id == id)
        .firstOrNull;
    final catalog = context.watch<CatalogCubit>().state.tracks;
    final map = {for (final track in catalog) track.id: track};
    final tracks = (playlist?.trackIds ?? [])
        .map((id) => map[id])
        .whereType<Track>()
        .toList();
    final missing =
        playlist?.trackIds.where((id) => !map.containsKey(id)).toList() ??
        <String>[];
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist telah dihapus.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: 'Ubah nama playlist',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await editPlaylistName(
                context,
                initial: playlist.name,
              );
              if (name != null) await playlists.rename(id, name);
            },
          ),
          IconButton(
            tooltip: 'Hapus playlist',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Hapus playlist?'),
                  content: const Text('Lagu di Library tetap ada.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await playlists.delete(id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => context.read<PlayerCubit>().playCollection(
                            tracks.map((track) => track.id).toList(),
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Putar ${tracks.length} lagu'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Tambah lagu ke playlist',
                  icon: const Icon(Icons.add),
                  onPressed: () => _selectTracks(context, playlist),
                ),
              ],
            ),
          ),
          if (playlist.trackIds.length > tracks.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${playlist.trackIds.length - tracks.length} lagu belum ditemukan. Impor file musik yang sama untuk mencocokkannya kembali.',
              ),
            ),
          if (tracks.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Tambahkan lagu dari tombol + atau menu lagu.'),
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                itemCount: tracks.length,
                onReorderItem: (from, to) {
                  final ids = tracks.map((track) => track.id).toList();
                  final item = ids.removeAt(from);
                  ids.insert(to, item);
                  playlists.setTracks(id, ids);
                },
                itemBuilder: (context, index) => Row(
                  key: ValueKey(tracks[index].id),
                  children: [
                    Expanded(child: TrackTile(track: tracks[index])),
                    IconButton(
                      tooltip: 'Keluarkan dari playlist',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => playlists.setTracks(
                        id,
                        tracks
                            .where((track) => track.id != tracks[index].id)
                            .map((track) => track.id)
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (missing.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.builder(
                itemCount: missing.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.music_off_outlined),
                  title: Text(
                    playlist.trackLabels[missing[index]] ??
                        'Lagu belum tersedia',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text(
                    'Impor file musik yang sama untuk mencocokkan',
                  ),
                  trailing: IconButton(
                    tooltip: 'Keluarkan lagu yang belum tersedia',
                    icon: const Icon(Icons.close),
                    onPressed: () => playlists.setTracks(
                      id,
                      playlist.trackIds
                          .where((trackId) => trackId != missing[index])
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _selectTracks(BuildContext context, MusicPlaylist playlist) {
    final collections = context.read<PlaylistCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: BlocBuilder<PlaylistCubit, PlaylistState>(
            bloc: collections,
            builder: (context, state) {
              final selected = state.playlists
                  .where((list) => list.id == id)
                  .firstOrNull;
              final tracks = context.watch<CatalogCubit>().state.tracks;
              return ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) => CheckboxListTile(
                  title: Text(tracks[index].title),
                  subtitle: Text(tracks[index].artist),
                  value: selected?.trackIds.contains(tracks[index].id) ?? false,
                  onChanged: (checked) {
                    if (selected == null) return;
                    collections.setTracks(
                      id,
                      checked == true
                          ? [...selected.trackIds, tracks[index].id]
                          : selected.trackIds
                                .where((entry) => entry != tracks[index].id)
                                .toList(),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TrackCollectionScreen extends StatelessWidget {
  const TrackCollectionScreen({
    super.key,
    required this.title,
    this.artist,
    this.album,
    this.liked = false,
  });
  final String title;
  final String? artist;
  final String? album;
  final bool liked;
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state.tracks;
    final likes = context.watch<LibraryCubit>().state.likes;
    final playlists = context.watch<PlaylistCubit>();
    final tracks = playlists.sorted(
      catalog.where(
        (track) =>
            (artist == null || track.artist == artist) &&
            (album == null || track.album == album) &&
            (!liked || likes.contains(track.id)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: tracks.isEmpty
                  ? null
                  : () => context.read<PlayerCubit>().playCollection(
                      tracks.map((track) => track.id).toList(),
                    ),
              icon: const Icon(Icons.play_arrow),
              label: Text('Putar ${tracks.length} lagu'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (_, index) => TrackTile(track: tracks[index]),
            ),
          ),
        ],
      ),
    );
  }
}
```

### lib/features/library/presentation/library_sections.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/domain/saved_music_folder.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../domain/music_playlist.dart';
import 'collection_screens.dart';
import 'playlist_cubit.dart';
import 'track_actions.dart';

class SavedFolderCard extends StatelessWidget {
  const SavedFolderCard({super.key, required this.folder});
  final SavedMusicFolder folder;
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>();
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              folder.error == null
                  ? Icons.folder_outlined
                  : Icons.folder_off_outlined,
            ),
            title: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              folder.error ?? '${folder.fingerprints.length} file dikenali',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Pindai ulang ${folder.name}',
                  icon: const Icon(Icons.refresh),
                  onPressed: catalog.state.importing
                      ? null
                      : () => catalog.rescanFolder(folder.id),
                ),
                IconButton(
                  tooltip: 'Lepas folder ${folder.name}',
                  icon: const Icon(Icons.link_off),
                  onPressed: catalog.state.importing
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Lepas sumber folder?'),
                              content: const Text(
                                'Salinan lagu di Library tetap ada. Pemindaian otomatis folder ini akan dihentikan.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Batal'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Lepas'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await catalog.forgetFolder(folder.id);
                          }
                        },
                ),
              ],
            ),
          ),
          SwitchListTile.adaptive(
            dense: true,
            title: const Text(
              'Deteksi lagu baru saat aplikasi aktif',
              style: TextStyle(fontSize: 12),
            ),
            value: folder.autoScan,
            onChanged: catalog.state.importing
                ? null
                : (value) => catalog.setAutoScan(folder.id, value),
          ),
        ],
      ),
    );
  }
}

class PlaylistsHeading extends StatelessWidget {
  const PlaylistsHeading({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'Playlist saya',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        tooltip: 'Buat playlist',
        icon: const Icon(Icons.playlist_add),
        onPressed: () async {
          final id = await createPlaylist(context);
          if (id != null && context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => PlaylistScreen(id: id)),
            );
          }
        },
      ),
    ],
  );
}

class UserPlaylistCard extends StatelessWidget {
  const UserPlaylistCard({super.key, required this.playlist});
  final MusicPlaylist playlist;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.playlist_play, color: AppTheme.green),
    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${playlist.trackIds.length} lagu'),
    trailing: IconButton(
      tooltip: 'Putar playlist ${playlist.name}',
      icon: const Icon(Icons.play_circle_fill, color: AppTheme.green),
      onPressed: playlist.trackIds.isEmpty
          ? null
          : () => context.read<PlayerCubit>().playCollection(playlist.trackIds),
    ),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PlaylistScreen(id: playlist.id)),
    ),
  );
}

class LibrarySortButton extends StatelessWidget {
  const LibrarySortButton({super.key});
  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlaylistCubit>();
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Urutkan lagu',
      initialValue: cubit.state.sort,
      onSelected: cubit.setSort,
      itemBuilder: (_) => LibrarySort.values
          .map((sort) => PopupMenuItem(value: sort, child: Text(sort.label)))
          .toList(),
      icon: const Icon(Icons.sort),
    );
  }
}
```

### lib/features/library/presentation/track_actions.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import 'playlist_cubit.dart';

Future<String?> editPlaylistName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(initial: initial),
    );

Future<String?> createPlaylist(BuildContext context) async {
  final cubit = context.read<PlaylistCubit>();
  final name = await editPlaylistName(context);
  return name == null ? null : cubit.create(name);
}

Future<void> addToPlaylist(BuildContext context, Track track) async {
  final playlists = context.read<PlaylistCubit>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: BlocBuilder<PlaylistCubit, PlaylistState>(
        bloc: playlists,
        builder: (context, state) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Tambahkan ke playlist',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Playlist baru'),
              onTap: () async {
                final name = await editPlaylistName(sheetContext);
                if (name == null) return;
                final id = await playlists.create(name);
                if (id != null) await playlists.addTrack(id, track.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            for (final list in state.playlists)
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(list.name),
                trailing: list.trackIds.contains(track.id)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () async {
                  await playlists.addTrack(list.id, track.id);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showTrackActions(BuildContext context, Track track) async {
  final catalog = context.read<CatalogCubit>();
  final player = context.read<PlayerCubit>();
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(track.artist),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Tambahkan ke playlist'),
            onTap: () => Navigator.pop(context, 'playlist'),
          ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Tambahkan ke antrean'),
            onTap: () => Navigator.pop(context, 'queue'),
          ),
          if (track.isLocal && catalog.canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus dari Library'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'playlist') {
    await addToPlaylist(context, track);
  }
  if (action == 'queue') {
    await player.enqueue(track.id);
  }
  if (action == 'delete') {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus dari Library?'),
        content: Text(
          'Salinan “${track.title}” di aplikasi akan dihapus. File asli di folder Anda tetap ada. '
          'Lagu ini juga dikeluarkan dari playlist dan antrean. Pilih folder lagi untuk mengimpornya kembali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) await catalog.removeLocalTrack(track.id);
  }
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.initial});
  final String initial;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial.isEmpty ? 'Buat playlist' : 'Ubah nama playlist',
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Nama playlist'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}
```

### lib/features/player/presentation/widgets/sleep_timer_sheet.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../player_cubit.dart';

Future<void> showSleepTimer(BuildContext context) {
  final player = context.read<PlayerCubit>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: BlocBuilder<PlayerCubit, PlayerState>(
        bloc: player,
        builder: (context, state) {
          final deadline = state.sleep['deadlineMs'];
          final until = deadline is int
              ? DateTime.fromMillisecondsSinceEpoch(deadline)
              : null;
          final time = until == null
              ? ''
              : '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
          Future<void> select(String mode, {int? minutes}) async {
            await player.setSleepTimer(mode, minutes: minutes);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text(
                    'Sleep timer',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                  ),
                  subtitle: Text(
                    until != null
                        ? 'Aktif hingga $time. Musik akan dijeda.'
                        : state.sleep['trackId'] != null
                        ? 'Aktif: jeda setelah lagu ini selesai.'
                        : 'Pilih kapan musik dijeda otomatis.',
                  ),
                ),
                for (final minutes in [15, 30, 60])
                  ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text('$minutes menit'),
                    onTap: () => select('duration', minutes: minutes),
                  ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: const Text('Setelah lagu ini selesai'),
                  subtitle: const Text(
                    'Berganti lagu secara manual membatalkan pilihan ini.',
                  ),
                  onTap: state.item == null ? null : () => select('track'),
                ),
                if (state.sleepActive)
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: const Text('Batalkan timer'),
                    onTap: () => select('cancel'),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(
                    'Timer memakai waktu berjalan, termasuk saat musik dijeda. Timer tidak dipulihkan setelah aplikasi dihentikan paksa.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
```

### lib/features/library/presentation/backup_screen.dart

```dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../data/collection_backup.dart';
import 'library_cubit.dart';
import 'playlist_cubit.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Proses gagal. Gunakan cadangan Swift Music JSON maksimal 2 MiB atau coba lokasi penyimpanan lain.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final backup = CollectionBackup(
      playlists: context
          .read<PlaylistCubit>()
          .state
          .playlists
          .map(
            (playlist) => playlist.copyWith(
              trackLabels: {
                ...playlist.trackLabels,
                for (final track in context.read<CatalogCubit>().state.tracks)
                  if (playlist.trackIds.contains(track.id))
                    track.id: '${track.title} — ${track.artist}',
              },
            ),
          )
          .toList(),
      likes: context.read<LibraryCubit>().state.likes,
    );
    final uri = await FilePicker.saveFile(
      fileName: 'swift-music-backup.json',
      bytes: Uint8List.fromList(backup.encode()),
      mimeType: 'application/json',
      dialogTitle: 'Simpan cadangan Swift Music',
    );
    if (mounted && uri != null) {
      setState(() => _message = 'Cadangan berhasil disimpan.');
    }
  });
  Future<void> _import() => _run(() async {
    final playlists = context.read<PlaylistCubit>();
    final library = context.read<LibraryCubit>();
    final catalog = context.read<CatalogCubit>();
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Pilih cadangan Swift Music',
    );
    if (file == null) return;
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > CollectionBackup.maxBytes) {
        throw const FormatException('Cadangan terlalu besar.');
      }
      bytes.addAll(chunk);
    }
    final backup = CollectionBackup.decode(bytes);
    final available = catalog.state.tracks.map((track) => track.id).toSet();
    final referenced = {
      ...backup.likes,
      for (final playlist in backup.playlists) ...playlist.trackIds,
    };
    final missing = referenced.difference(available).length;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pulihkan koleksi?'),
        content: Text(
          '${backup.playlists.length} playlist, ${backup.likes.length} favorit. $missing lagu belum tersedia di perangkat ini.\n\nKoleksi digabung tanpa menghapus playlist yang ada. File musik tidak disertakan; impor file asli yang sama untuk mencocokkan lagu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final added = await playlists.mergeBackup(backup.playlists);
    await library.mergeLikes(backup.likes);
    if (mounted) {
      setState(
        () => _message =
            '$added playlist ditambahkan. $missing lagu perlu diimpor kembali.',
      );
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cadangan koleksi')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Cadangkan playlist dan favorit ke file JSON. File musik, izin folder, dan lirik tidak disertakan. File musik yang sama akan dicocokkan berdasarkan isi saat diimpor pada perangkat baru.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.upload_file),
          label: const Text('Simpan cadangan'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.restore),
          label: const Text('Pulihkan cadangan'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(_message!),
          ),
      ],
    ),
  );
}
```

### lib/features/search/presentation/search_filters.dart

```dart
import 'package:flutter/material.dart';
import '../../catalog/domain/music_filter.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/domain/saved_music_folder.dart';

class SearchFilters extends StatefulWidget {
  const SearchFilters({
    super.key,
    required this.filter,
    required this.tracks,
    required this.folders,
    required this.onChanged,
  });
  final MusicFilter filter;
  final List<Track> tracks;
  final List<SavedMusicFolder> folders;
  final ValueChanged<MusicFilter> onChanged;
  @override
  State<SearchFilters> createState() => _SearchFiltersState();
}

class _SearchFiltersState extends State<SearchFilters> {
  bool _expanded = false;
  late final _artist = TextEditingController(text: widget.filter.artist ?? '');
  late final _album = TextEditingController(text: widget.filter.album ?? '');
  @override
  void didUpdateWidget(SearchFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_artist.text != (widget.filter.artist ?? '')) {
      _artist.text = widget.filter.artist ?? '';
    }
    if (_album.text != (widget.filter.album ?? '')) {
      _album.text = widget.filter.album ?? '';
    }
  }

  @override
  void dispose() {
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final folders = widget.folders;
    final onChanged = widget.onChanged;
    final extensions =
        (_expanded ? widget.tracks : <Track>[])
            .where((track) => track.isLocal)
            .map(
              (track) =>
                  Uri.parse(track.audioUrl).path.split('.').last.toLowerCase(),
            )
            .toSet()
            .toList()
          ..sort();
    Widget field(
      String label,
      String? value,
      Map<String, String> options,
      ValueChanged<String?> change,
    ) {
      final values = {
        ...options,
        if (value != null && !options.containsKey(value)) value: value,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label:$value'),
          initialValue: value ?? '',
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Semua')),
            for (final entry in values.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => change(value == '' ? null : value),
        ),
      );
    }

    void update({
      String? folder,
      String? extension,
      String? artist,
      String? album,
      String? duration,
    }) => onChanged(
      MusicFilter(
        folder: folder,
        extension: extension,
        artist: artist,
        album: album,
        duration: duration,
      ),
    );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(filter.active ? 'Filter koleksi aktif' : 'Filter koleksi'),
      leading: const Icon(Icons.tune),
      onExpansionChanged: (value) => setState(() => _expanded = value),
      children: !_expanded
          ? []
          : [
              field(
                'Folder',
                filter.folder,
                {for (final folder in folders) folder.id: folder.name},
                (value) => update(
                  folder: value,
                  extension: filter.extension,
                  artist: filter.artist,
                  album: filter.album,
                  duration: filter.duration,
                ),
              ),
              field(
                'Format',
                filter.extension,
                {for (final ext in extensions) ext: ext.toUpperCase()},
                (value) => update(
                  folder: filter.folder,
                  extension: value,
                  artist: filter.artist,
                  album: filter.album,
                  duration: filter.duration,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _artist,
                  decoration: const InputDecoration(labelText: 'Artis'),
                  onChanged: (value) => update(
                    folder: filter.folder,
                    extension: filter.extension,
                    artist: value.isEmpty ? null : value,
                    album: filter.album,
                    duration: filter.duration,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _album,
                  decoration: const InputDecoration(labelText: 'Album'),
                  onChanged: (value) => update(
                    folder: filter.folder,
                    extension: filter.extension,
                    artist: filter.artist,
                    album: value.isEmpty ? null : value,
                    duration: filter.duration,
                  ),
                ),
              ),
              field(
                'Durasi',
                filter.duration,
                const {
                  'short': 'Maksimal 3 menit',
                  'long': 'Lebih dari 3 menit',
                  'unknown': 'Durasi belum diketahui',
                },
                (value) => update(
                  folder: filter.folder,
                  extension: filter.extension,
                  artist: filter.artist,
                  album: filter.album,
                  duration: value,
                ),
              ),
              if (filter.active)
                TextButton(
                  onPressed: () => onChanged(const MusicFilter()),
                  child: const Text('Reset filter'),
                ),
            ],
    );
  }
}
```

