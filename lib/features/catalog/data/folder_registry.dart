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
