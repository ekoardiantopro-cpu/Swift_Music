class ServiceLink {
  static String youtube(String input) {
    if (RegExp(r'^[\w-]{11}$').hasMatch(input.trim())) return input.trim();
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException(
        'Masukkan tautan HTTPS YouTube atau YouTube Music.',
      );
    }
    String? id;
    if (uri.host == 'youtu.be') {
      id = uri.pathSegments.firstOrNull;
    } else if ({
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
    }.contains(uri.host)) {
      id = uri.queryParameters['v'];
      if (id == null &&
          uri.pathSegments.length == 2 &&
          {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments.last;
      }
    }
    if (id == null || !RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      throw const FormatException(
        'Tautan harus menunjuk ke satu video/lagu YouTube.',
      );
    }
    return id;
  }

  static String spotify(String input) {
    final uri = Uri.tryParse(input.trim());
    List<String> parts = [];
    if (uri?.scheme == 'spotify') {
      parts = uri!.path.split(':');
    }
    if (uri?.scheme == 'https' && uri?.host == 'open.spotify.com') {
      parts = uri!.pathSegments.where((p) => !p.startsWith('intl-')).toList();
    }
    if (parts.length != 2 ||
        !{'track', 'album', 'playlist', 'episode', 'show'}.contains(parts[0]) ||
        !RegExp(r'^[a-zA-Z0-9]{22}$').hasMatch(parts[1])) {
      throw const FormatException(
        'Masukkan tautan track, album atau playlist dari open.spotify.com.',
      );
    }
    return '${parts[0]}/${parts[1]}';
  }
}
