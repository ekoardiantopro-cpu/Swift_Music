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
