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
