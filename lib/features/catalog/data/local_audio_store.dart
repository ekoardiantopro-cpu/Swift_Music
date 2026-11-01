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
        final audio = File(p.join(directory.path, filename));
        if (await audio.exists()) {
          if (record['metadataVersion'] != 2 &&
              _metadata is! NoAudioMetadataReader) {
            await _enrich(record);
            await _writeRecord(entry, record);
          }
          records.add(record);
        } else {
          record['_missing'] = true;
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
      final sizeBytes = await temporary.length();
      await temporary.rename(p.join(directory.path, filename));
      final record = <String, dynamic>{
        'id': 'local-$digest',
        'file': filename,
        'title': p.basenameWithoutExtension(name),
        'originalName': p.basename(name),
        'importedAt': DateTime.now().microsecondsSinceEpoch,
        'sizeBytes': sizeBytes,
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
      record['technical'] = tags;
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
    record['metadataVersion'] = 2;
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
    missing: record['_missing'] == true,
    info: {
      ...(record['technical'] is Map
          ? Map<String, dynamic>.from(record['technical'] as Map)
          : <String, dynamic>{}),
      'importedAt': record['importedAt'],
      'sizeBytes': record['sizeBytes'],
      'originalName': record['originalName'],
    },
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
