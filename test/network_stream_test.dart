import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/streaming/domain/network_playlist.dart';
import 'package:swift_music/features/streaming/domain/service_link.dart';
import 'package:swift_music/features/streaming/data/sponsor_block.dart';
import 'package:swift_music/features/streaming/data/network_subtitles.dart';
import 'package:swift_music/features/streaming/data/network_resolver.dart';

void main() {
  final base = Uri.parse('https://radio.example/list/channels.m3u8?token=test');
  test(
    'M3U unicode titles and relative URLs; HLS segments stay one manifest',
    () {
      final entries = NetworkPlaylist.parse(
        '#EXTM3U\n#EXTINF:-1,音楽\n../one.mp3\n# comment\nhttps://radio.example/two\n',
        base,
      );
      expect(entries.length, 2);
      expect(entries.first.title, '音楽');
      expect(entries.first.uri.toString(), 'https://radio.example/one.mp3');
      final hls = NetworkPlaylist.parse(
        '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts\n',
        base,
      );
      expect(hls.length, 1);
      expect(hls.first.uri, base);
      expect(hls.first.kind, 'hls');
    },
  );
  test('PLS uses numeric order; XML formats resolve escaped and namespaced URLs', () {
    final pls = NetworkPlaylist.parse(
      '[playlist]\nFile10=https://a.test/10\nFile2=https://a.test/2\nTitle2=Second',
      base,
    );
    expect(pls.first.title, 'Second');
    for (final text in [
      '<playlist xmlns="http://xspf.org/ns/0/"><trackList><track><title>Radio</title><location>../live?a=1&amp;b=2</location></track></trackList></playlist>',
      '<ASX><ENTRY><TITLE>Radio</TITLE><REF HREF="../live?a=1&amp;b=2"/></ENTRY></ASX>',
      '<smil><body><seq><media src="../live?a=1&amp;b=2" title="Radio"/></seq></body></smil>',
    ]) {
      final entries = NetworkPlaylist.parse(text, base);
      expect(entries.single.title, 'Radio');
      expect(entries.single.uri.queryParameters['b'], '2');
    }
  });
  test(
    'invalid and oversized playlists cannot load local files or XML entities',
    () {
      expect(
        () => NetworkPlaylist.parse('file:///private/secret', base),
        throwsFormatException,
      );
      expect(
        () => NetworkPlaylist.parse(
          '<!DOCTYPE x [<!ENTITY a SYSTEM "file:///secret">]><x/>',
          base,
        ),
        throwsFormatException,
      );
      expect(
        () => NetworkPlaylist.parse(
          List.filled(1001, 'https://a.test/stream').join('\n'),
          base,
        ),
        throwsFormatException,
      );
      expect(
        NetworkPlaylist.limitation(Uri.parse('rtsp://camera.test/live')),
        contains('eksternal'),
      );
      expect(
        NetworkPlaylist.limitation(Uri.parse('https://a.test/chunk.m4s')),
        contains('manifest'),
      );
      expect(
        NetworkPlaylist.limitation(
          Uri.parse('https://a.test/main.mpd'),
          ios: true,
        ),
        contains('iOS'),
      );
    },
  );
  test('service links require exact hosts and valid IDs', () {
    expect(
      ServiceLink.youtube('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      ServiceLink.youtube('https://youtu.be/dQw4w9WgXcQ?t=3'),
      'dQw4w9WgXcQ',
    );
    expect(
      () => ServiceLink.youtube(
        'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
      ),
      throwsFormatException,
    );
    expect(
      ServiceLink.spotify(
        'https://open.spotify.com/intl-id/track/4cOdK2wGLETKBW3PvgPWqT?si=test',
      ),
      'track/4cOdK2wGLETKBW3PvgPWqT',
    );
    expect(
      () =>
          ServiceLink.spotify('https://evil.test/track/4cOdK2wGLETKBW3PvgPWqT'),
      throwsFormatException,
    );
  });
  test(
    'SponsorBlock filters categories and malformed intervals; merges overlaps',
    () {
      final rows = [
        {
          'category': 'sponsor',
          'actionType': 'skip',
          'segment': [0, 15],
        },
        {
          'category': 'sponsor',
          'actionType': 'skip',
          'segment': [12, 20],
        },
        {
          'category': 'intro',
          'actionType': 'skip',
          'segment': [20, 30],
        },
        {
          'category': 'sponsor',
          'actionType': 'skip',
          'segment': [30, 29],
        },
        {
          'category': 'sponsor',
          'actionType': 'skip',
          'segment': [double.nan, 40],
        },
      ];
      final segments = SponsorSegment.parse(rows);
      expect(segments.length, 1);
      expect(segments.single.start, 0);
      expect(segments.single.end, 20);
    },
  );
  test('SRT and VTT become synchronized lyrics', () {
    expect(
      NetworkSubtitles.toLyrics(
        '1\n00:01:02,340 --> 00:01:05,000\nHello\nworld\n',
      ),
      '[1:02.34]Hello world',
    );
    expect(
      NetworkSubtitles.toLyrics(
        'WEBVTT\n\n00:02.100 --> 00:04.000\n<b>Music</b>\n',
      ),
      '[0:02.10]Music',
    );
  });
  test(
    'HTTP resolver follows redirects relative to final URL; bounds errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        if (request.uri.path == '/start.m3u') {
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/final/list.m3u');
        } else if (request.uri.path == '/final/list.m3u') {
          request.response.write('#EXTM3U\n../song.mp3');
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      try {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/start.m3u');
        final entries = await NetworkResolver().resolve(uri);
        expect(entries.single.uri.path, '/song.mp3');
        await expectLater(
          NetworkResolver().resolve(uri.replace(path: '/missing.pls')),
          throwsFormatException,
        );
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
