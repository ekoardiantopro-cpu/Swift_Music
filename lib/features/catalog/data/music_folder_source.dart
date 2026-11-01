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
