class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class LrcDocument {
  LrcDocument._(this.lines);
  final List<LyricLine> lines;
  bool get synced => lines.isNotEmpty;
  static final _timestamp = RegExp(
    r'\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]',
  );
  static LrcDocument parse(String raw) {
    final offsetMatch = RegExp(
      r'\[offset:([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
    final timed = <int, List<String>>{};
    for (final line in raw.replaceAll('\uFEFF', '').split(RegExp(r'\r?\n'))) {
      final stamps = _timestamp.allMatches(line).toList();
      if (stamps.isEmpty) continue;
      final text = line
          .replaceAll(_timestamp, '')
          .replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:\.\d{1,3})?>'), '')
          .trim();
      for (final match in stamps) {
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final ms =
            (int.parse(match.group(1)!) * 60000 +
                    int.parse(match.group(2)!) * 1000 +
                    int.parse(fraction) -
                    offset)
                .clamp(0, 1 << 52);
        final texts = timed.putIfAbsent(ms, () => []);
        if (!texts.contains(text)) texts.add(text);
      }
    }
    final entries = timed.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return LrcDocument._(
      List.unmodifiable(
        entries.map(
          (entry) => LyricLine(
            Duration(milliseconds: entry.key),
            entry.value.join('\n'),
          ),
        ),
      ),
    );
  }

  int activeIndex(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
