import 'package:xml/xml.dart';

class StreamEntry {
  const StreamEntry(this.uri, this.title, {this.kind = 'auto'});
  final Uri uri;
  final String title;
  final String kind;
  Map<String, dynamic> toJson() => {
    'url': uri.toString(),
    'title': title,
    'kind': kind,
  };
}

class NetworkPlaylist {
  static String _attribute(XmlElement element, String name) =>
      element.attributes
          .where((a) => a.name.local.toLowerCase() == name)
          .firstOrNull
          ?.value ??
      '';
  static const extensions = {
    'm3u',
    'm3u8',
    'xspf',
    'pls',
    'wpl',
    'asx',
    'wax',
    'wvx',
  };
  static String extension(Uri uri) =>
      uri.path.split('/').last.split('.').last.toLowerCase();
  static Uri address(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        !{
          'http',
          'https',
          'rtsp',
          'rtmp',
          'rtmps',
          'rtmpe',
          'mms',
          'ftp',
          'udp',
          'rtp',
        }.contains(uri.scheme.toLowerCase())) {
      throw const FormatException(
        'Masukkan URL stream lengkap dengan protokol dan alamat server.',
      );
    }
    return uri;
  }

  static String? limitation(Uri uri, {bool ios = false}) {
    if (!{'http', 'https'}.contains(uri.scheme)) {
      return 'Protokol ${uri.scheme} belum didukung pemutar internal. Gunakan tautan HTTP/HTTPS atau buka melalui aplikasi eksternal.';
    }
    final ext = extension(uri);
    if (ext == 'm4s') {
      return 'Segmen .m4s membutuhkan manifest .mpd atau .m3u8 beserta init segment.';
    }
    if (ext == 'ism' ||
        ext == 'isml' ||
        uri.path.toLowerCase().contains('.ism/manifest')) {
      return 'Smooth Streaming belum didukung pemutar internal ini.';
    }
    if (ios && ext == 'mpd') {
      return 'MPEG-DASH belum didukung AVPlayer di iOS. Gunakan HLS (.m3u8).';
    }
    return null;
  }

  static List<StreamEntry> parse(String text, Uri base) {
    if (text.length > 2 * 1024 * 1024) {
      throw const FormatException('Playlist terlalu besar (maksimal 2 MB).');
    }
    final source = text.replaceFirst('\uFEFF', '').trim();
    if (source.contains(RegExp(r'^#EXT-X-', multiLine: true))) {
      return [StreamEntry(base, 'HLS · ${base.host}', kind: 'hls')];
    }
    final result = <StreamEntry>[];
    void add(String raw, String title) {
      if (raw.trim().isEmpty) return;
      if (result.length >= 1000) {
        throw const FormatException('Maksimal 1.000 entri per playlist.');
      }
      final uri = base.resolve(raw.trim());
      if (!{
            'http',
            'https',
            'rtsp',
            'rtmp',
            'rtmps',
            'rtmpe',
            'mms',
            'ftp',
            'udp',
            'rtp',
          }.contains(uri.scheme) ||
          uri.host.isEmpty) {
        return;
      }
      result.add(
        StreamEntry(
          uri,
          title.trim().isEmpty
              ? 'Stream ${result.length + 1} · ${uri.host}'
              : title.trim(),
        ),
      );
    }

    if (source.startsWith('<')) {
      if (source.toUpperCase().contains('<!DOCTYPE') ||
          source.toUpperCase().contains('<!ENTITY')) {
        throw const FormatException('Deklarasi XML eksternal tidak didukung.');
      }
      final doc = XmlDocument.parse(source);
      final root = doc.rootElement.name.local.toLowerCase();
      if (root == 'mpd' || root == 'smoothstreamingmedia') {
        return [
          StreamEntry(
            base,
            'Manifest · ${base.host}',
            kind: root == 'mpd' ? 'dash' : 'smooth',
          ),
        ];
      }
      final groups = doc.descendants.whereType<XmlElement>().where(
        (e) => {'track', 'entry'}.contains(e.name.local.toLowerCase()),
      );
      for (final group in groups) {
        final title =
            group.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local.toLowerCase() == 'title')
                .firstOrNull
                ?.innerText ??
            '';
        for (final element in group.descendants.whereType<XmlElement>()) {
          final name = element.name.local.toLowerCase();
          if (name == 'location') add(element.innerText, title);
          if (name == 'ref') add(_attribute(element, 'href'), title);
        }
      }
      for (final element in doc.descendants.whereType<XmlElement>()) {
        if (element.name.local.toLowerCase() == 'media') {
          add(_attribute(element, 'src'), _attribute(element, 'title'));
        }
        if (element.name.local.toLowerCase() == 'entryref') {
          add(_attribute(element, 'href'), '');
        }
      }
    } else if (source.toLowerCase().startsWith('[playlist]')) {
      final fields = <String, String>{};
      for (final line in source.split(RegExp(r'\r?\n'))) {
        final at = line.indexOf('=');
        if (at > 0) {
          fields[line.substring(0, at).trim().toLowerCase()] = line
              .substring(at + 1)
              .trim();
        }
      }
      final numbers =
          fields.keys
              .where((k) => RegExp(r'^file\d+$').hasMatch(k))
              .map((k) => int.parse(k.substring(4)))
              .toList()
            ..sort();
      for (final n in numbers) {
        add(fields['file$n']!, fields['title$n'] ?? '');
      }
    } else {
      var title = '';
      for (final raw in source.split(RegExp(r'\r?\n'))) {
        final line = raw.trim();
        if (line.startsWith('#EXTINF:')) {
          final comma = line.indexOf(',');
          title = comma < 0 ? '' : line.substring(comma + 1);
        } else if (line.isNotEmpty && !line.startsWith('#')) {
          add(line, title);
          title = '';
        }
      }
    }
    final unique = <String, StreamEntry>{};
    for (final entry in result) {
      unique.putIfAbsent(entry.uri.toString(), () => entry);
    }
    if (unique.isEmpty) {
      throw const FormatException(
        'Playlist tidak berisi alamat stream yang dapat dibaca.',
      );
    }
    return unique.values.toList();
  }
}
