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
    Future<void> Function(String)? repair,
    Future<void> Function()? onRepaired,
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
       _repair = repair,
       _onRepaired = onRepaired,
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
  final Future<void> Function(String)? _repair;
  final Future<void> Function()? _onRepaired;
  Future<void> repairLocalTrack(String id) async {
    if (state.importing || _repair == null) return;
    try {
      await _repair(id);
      await _onRepaired?.call();
      if (!isClosed) {
        emit(
          _snapshot(
            message:
                'Pemilihan file selesai. Lagu yang cocok sudah dapat dicoba kembali.',
          ),
        );
      }
    } catch (error) {
      if (!isClosed) {
        emit(
          _snapshot(
            message: error is FormatException
                ? error.message
                : 'File belum dapat dihubungkan. Pilih file asli yang sama.',
          ),
        );
      }
    }
  }

  bool _cancelled = false;
  bool get canRemove => _removeTrack != null;
  void refresh() {
    if (!isClosed && !state.importing) emit(_snapshot());
  }

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
