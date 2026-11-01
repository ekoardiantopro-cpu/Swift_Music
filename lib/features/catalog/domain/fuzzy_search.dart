import 'track.dart';

abstract final class FuzzyMusicSearch {
  static int? score(String query, String text) {
    final needle = query.trim().toLowerCase();
    final haystack = text.toLowerCase();
    if (needle.isEmpty || haystack.contains(needle)) return 0;
    final tokens = needle.split(RegExp(r'\s+')).where((v) => v.isNotEmpty);
    final words = haystack
        .split(RegExp(r'[\s_.,:;!?()\[\]/\\-]+'))
        .where((v) => v.isNotEmpty)
        .toList();
    var total = 0;
    for (final token in tokens) {
      if (words.any((word) => word.contains(token))) continue;
      if (token.length < 3 || token.length > 100) return null;
      final limit = token.length >= 7 ? 2 : 1;
      var best = limit + 1;
      for (final word in words) {
        if ((word.length - token.length).abs() > limit) continue;
        var row = List.generate(word.length + 1, (i) => i);
        List<int>? earlier;
        for (var i = 1; i <= token.length; i++) {
          final next = List.filled(word.length + 1, 0)..[0] = i;
          for (var j = 1; j <= word.length; j++) {
            final replace =
                row[j - 1] +
                (token.codeUnitAt(i - 1) == word.codeUnitAt(j - 1) ? 0 : 1);
            final insert = next[j - 1] + 1;
            final delete = row[j] + 1;
            next[j] = replace < insert
                ? (replace < delete ? replace : delete)
                : (insert < delete ? insert : delete);
            if (earlier != null &&
                i > 1 &&
                j > 1 &&
                token.codeUnitAt(i - 1) == word.codeUnitAt(j - 2) &&
                token.codeUnitAt(i - 2) == word.codeUnitAt(j - 1)) {
              final swapped = earlier[j - 2] + 1;
              if (swapped < next[j]) next[j] = swapped;
            }
          }
          earlier = row;
          row = next;
        }
        if (row.last < best) best = row.last;
      }
      if (best > limit) return null;
      total += best;
    }
    return total + 1;
  }

  static List<Track> search(Iterable<Track> tracks, String query) {
    final ranked = <(Track, int, int)>[];
    for (final track in tracks) {
      final value = score(query, '${track.title} ${track.artist}');
      if (value != null) ranked.add((track, value, ranked.length));
    }
    ranked.sort(
      (a, b) => a.$2 == b.$2 ? a.$3.compareTo(b.$3) : a.$2.compareTo(b.$2),
    );
    return ranked.map((entry) => entry.$1).toList();
  }
}
