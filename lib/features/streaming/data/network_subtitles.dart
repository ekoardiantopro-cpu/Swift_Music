import 'dart:async';
import 'dart:convert';
import 'dart:io';

class NetworkSubtitles {
  static String toLyrics(String text) {
    if (RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(text)) return text;
    final lines = text.replaceAll('\r', '').split('\n');
    final output = <String>[];
    final stamp = RegExp(r'^(?:(\d{2}):)?(\d{2}):(\d{2})[,.](\d{3})\s+-->');
    for (var i = 0; i < lines.length; i++) {
      final match = stamp.firstMatch(lines[i]);
      if (match == null) continue;
      final minutes = int.parse(match[1] ?? '0') * 60 + int.parse(match[2]!);
      final words = <String>[];
      while (++i < lines.length && lines[i].trim().isNotEmpty) {
        words.add(lines[i].replaceAll(RegExp('<[^>]*>'), '').trim());
      }
      if (words.isNotEmpty) {
        output.add(
          '[$minutes:${match[3]}.${match[4]!.substring(0, 2)}]${words.join(' ')}',
        );
      }
    }
    return output.join('\n');
  }

  Future<String?> scan(Uri media) async {
    if (!{'http', 'https'}.contains(media.scheme)) return null;
    final last = media.path.lastIndexOf('.');
    final slash = media.path.lastIndexOf('/');
    final base = last > slash ? media.path.substring(0, last) : media.path;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final deadline = Timer(
      const Duration(seconds: 10),
      () => client.close(force: true),
    );
    try {
      for (final extension in ['lrc', 'vtt', 'srt']) {
        try {
          final request = await client
              .getUrl(media.replace(path: '$base.$extension'))
              .timeout(const Duration(seconds: 3));
          request.maxRedirects = 2;
          final response = await request.close().timeout(
            const Duration(seconds: 3),
          );
          final bytes = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 3),
          )) {
            if (bytes.length + chunk.length > 256 * 1024) {
              throw const FormatException('Subtitle too large');
            }
            bytes.addAll(chunk);
          }
          if (response.statusCode != 200) continue;
          final text = toLyrics(utf8.decode(bytes));
          if (text.isNotEmpty) return text;
        } catch (_) {
          /* Missing sidecars must never prevent playback. */
        }
      }
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
    return null;
  }
}
