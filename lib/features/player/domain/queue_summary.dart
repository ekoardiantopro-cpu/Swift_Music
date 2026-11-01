class QueueSummary {
  QueueSummary({
    required List<Duration?> durations,
    required int currentIndex,
    required Duration position,
    required double speed,
    required bool shuffled,
    required DateTime now,
  }) {
    total = durations.fold(
      Duration.zero,
      (sum, duration) => sum + (duration ?? Duration.zero),
    );
    unknown = durations.where((d) => d == null).length;
    if (unknown == 0 &&
        !shuffled &&
        speed > 0 &&
        currentIndex >= 0 &&
        currentIndex < durations.length) {
      final after = durations
          .skip(currentIndex)
          .fold(Duration.zero, (sum, duration) => sum + duration!);
      final remainingMs = (after - position).inMilliseconds;
      eta = now.add(
        Duration(
          milliseconds: ((remainingMs < 0 ? 0 : remainingMs) / speed).round(),
        ),
      );
    }
  }
  late final Duration total;
  late final int unknown;
  DateTime? eta;
  String get label {
    final minutes = total.inMinutes;
    final duration = minutes >= 60
        ? '${minutes ~/ 60} jam ${minutes % 60} menit'
        : '$minutes menit';
    final end = eta;
    return 'Total $duration${unknown > 0 ? ' + $unknown lagu tanpa durasi' : ''}${end == null ? '' : ' • selesai ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'}';
  }
}
