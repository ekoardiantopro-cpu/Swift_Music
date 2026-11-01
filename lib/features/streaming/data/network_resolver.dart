import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../domain/network_playlist.dart';

/// One short-lived client per request; stream audio never passes through Dart RAM.
class NetworkResolver {
  Future<List<StreamEntry>> resolve(
    Uri uri, {
    bool forcePlaylist = false,
    int depth = 0,
  }) async {
    final ext = NetworkPlaylist.extension(uri);
    if (!forcePlaylist && !NetworkPlaylist.extensions.contains(ext)) {
      return [StreamEntry(uri, 'Stream · ${uri.host}')];
    }
    if (!{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException(
        'Playlist jarak jauh harus menggunakan HTTP/HTTPS.',
      );
    }
    if (depth > 3) {
      throw const FormatException('Terlalu banyak playlist bertingkat.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final deadline = Timer(
      const Duration(seconds: 18),
      () => client.close(force: true),
    );
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.maxRedirects = 4;
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw FormatException(
          'Server mengembalikan HTTP ${response.statusCode}.',
        );
      }
      var base = uri;
      for (final redirect in response.redirects) {
        base = base.resolveUri(redirect.location);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException('Playlist melebihi batas 2 MB.');
        }
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes, allowMalformed: ext == 'm3u');
      final entries = NetworkPlaylist.parse(text, base);
      if (entries.length == 1 &&
          entries.first.kind == 'auto' &&
          entries.first.uri != base &&
          NetworkPlaylist.extensions.contains(
            NetworkPlaylist.extension(entries.first.uri),
          )) {
        return await resolve(entries.first.uri, depth: depth + 1);
      }
      return entries;
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
  }
}
