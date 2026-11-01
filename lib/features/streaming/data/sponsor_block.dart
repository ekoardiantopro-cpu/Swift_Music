import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class SponsorSegment {
  const SponsorSegment(this.start, this.end);
  final double start, end;
  static List<SponsorSegment> parse(dynamic rows) {
    final segments = <SponsorSegment>[];
    if (rows is! List) return segments;
    for (final row in rows.whereType<Map>()) {
      final times = row['segment'];
      if (row['category'] != 'sponsor' ||
          row['actionType'] != 'skip' ||
          times is! List ||
          times.length != 2) {
        continue;
      }
      final a = times[0], b = times[1];
      if (a is num && b is num && a.isFinite && b.isFinite && a >= 0 && b > a) {
        segments.add(SponsorSegment(a.toDouble(), b.toDouble()));
      }
    }
    segments.sort((a, b) => a.start.compareTo(b.start));
    final merged = <SponsorSegment>[];
    for (final segment in segments) {
      if (merged.isNotEmpty && segment.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add(
          SponsorSegment(
            last.start,
            segment.end > last.end ? segment.end : last.end,
          ),
        );
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }
}

class SponsorBlock {
  Future<List<SponsorSegment>> fetch(String videoId) async {
    final prefix = sha256
        .convert(utf8.encode(videoId))
        .toString()
        .substring(0, 4);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(
            Uri.https('sponsor.ajay.app', '/api/skipSegments/$prefix', {
              'categories': '["sponsor"]',
              'actionTypes': '["skip"]',
            }),
          )
          .timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode == 404) return [];
      if (response.statusCode != 200) {
        throw const HttpException('SponsorBlock unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 6))) {
        if (bytes.length + chunk.length > 512 * 1024) {
          throw const FormatException('Response too large');
        }
        bytes.addAll(chunk);
      }
      final rows = jsonDecode(utf8.decode(bytes));
      if (rows is! List) return [];
      for (final row in rows.whereType<Map>()) {
        if (row['videoID'] == videoId) {
          return SponsorSegment.parse(row['segments']);
        }
      }
      return [];
    } finally {
      client.close(force: true);
    }
  }
}
