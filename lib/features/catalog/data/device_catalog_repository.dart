import 'package:file_picker/file_picker.dart';
import '../domain/catalog_repository.dart';
import '../domain/track.dart';
import 'demo_catalog_repository.dart';
import 'local_audio_store.dart';
import 'music_folder_source.dart';
import 'folder_registry.dart';
import '../domain/saved_music_folder.dart';
import '../domain/fuzzy_search.dart';
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
  Track Function(Track)? decorate;
  late final Set<String> _knownIds = _tracks.map((track) => track.id).toSet();
  @override
  List<Track> get tracks =>
      List.unmodifiable(_tracks.map((track) => decorate?.call(track) ?? track));
  Future<void> repairTrack(String id) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: LocalAudioStore.extensions,
      dialogTitle: 'Pilih file asli untuk lagu yang hilang',
    );
    if (file == null) return;
    final digest = await sha256.bind(file.readAsByteStream()).first;
    if ('local-$digest' != id) {
      throw const FormatException(
        'Isi file berbeda. Pilih file asli yang sama; file berbeda dapat diimpor sebagai lagu baru melalui Library.',
      );
    }
    final track = await _store.importAudio(file.name, file.readAsByteStream());
    final index = _tracks.indexWhere((t) => t.id == id);
    if (index >= 0) _tracks[index] = track;
  }

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
          final index = _tracks.indexWhere((item) => item.id == track.id);
          if (index >= 0 && _tracks[index].missing) _tracks[index] = track;
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
            final index = _tracks.indexWhere((item) => item.id == track.id);
            if (index >= 0 && _tracks[index].missing) _tracks[index] = track;
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
    return FuzzyMusicSearch.search(
      tracks.where((track) => genre == null || track.genre == genre),
      query,
    );
  }
}
