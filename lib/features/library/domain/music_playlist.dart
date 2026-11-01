class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    List<String> trackIds = const [],
    Map<String, String> trackLabels = const {},
    this.description = '',
    this.folder = '',
    this.cover = '',
    List<Map<String, dynamic>> changes = const [],
  }) : trackIds = List.unmodifiable(trackIds.toSet()),
       trackLabels = Map.unmodifiable(trackLabels),
       changes = List.unmodifiable(changes);
  final String id;
  final String name;
  final List<String> trackIds;
  final Map<String, String> trackLabels;
  final String description, folder, cover;
  final List<Map<String, dynamic>> changes;
  MusicPlaylist copyWith({
    String? name,
    List<String>? trackIds,
    Map<String, String>? trackLabels,
    String? description,
    String? folder,
    String? cover,
    List<Map<String, dynamic>>? changes,
  }) => MusicPlaylist(
    id: id,
    name: name ?? this.name,
    trackIds: trackIds ?? this.trackIds,
    trackLabels: trackLabels ?? this.trackLabels,
    description: description ?? this.description,
    folder: folder ?? this.folder,
    cover: cover ?? this.cover,
    changes: changes ?? this.changes,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'trackLabels': trackLabels,
    'description': description,
    'folder': folder,
    'cover': cover,
    'changes': changes,
  };
  static MusicPlaylist fromJson(Map<String, dynamic> json) => MusicPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    trackIds: (json['trackIds'] as List).cast<String>(),
    trackLabels: json['trackLabels'] is Map
        ? Map<String, String>.from(json['trackLabels'] as Map)
        : {},
    description: json['description'] is String
        ? json['description'] as String
        : '',
    folder: json['folder'] is String ? json['folder'] as String : '',
    cover: json['cover'] is String ? json['cover'] as String : '',
    changes: (json['changes'] as List? ?? [])
        .whereType<Map>()
        .take(100)
        .map((v) => Map<String, dynamic>.from(v))
        .toList(),
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
