import 'planner_time_zone.dart';

/// Maps a planner-local calendar day onto elapsed time from its real local
/// midnight. Unlike a wall-clock minute-of-day, this remains one-to-one on
/// daylight-saving transition days: the spring gap is omitted and the autumn
/// repeated hour occupies two distinct positions.
final class PlannerDayAxis {
  final DateTime date;
  late final DateTime start;
  late final DateTime end;

  PlannerDayAxis(this.date) {
    final bounds = PlannerTimeZone.dayBounds(date);
    start = bounds.$1;
    end = bounds.$2;
  }

  int get durationMinutes => end.difference(start).inMinutes;

  double elapsedMinutes(DateTime instant) {
    final value =
        instant.toUtc().difference(start.toUtc()).inMicroseconds /
        Duration.microsecondsPerMinute;
    return value.clamp(0, durationMinutes).toDouble();
  }

  DateTime instantAt(double elapsed) {
    final minutes = elapsed.clamp(0, durationMinutes);
    return start.add(Duration(milliseconds: (minutes * 60000).round()));
  }

  /// Converts a wall-clock slot to an instant. The timezone package resolves
  /// a missing spring-forward time to the first valid instant after the gap;
  /// this keeps quick-create deterministic while the rendered axis remains
  /// elapsed-time based.
  DateTime instantForWallClockMinute(int minute) {
    final local = PlannerTimeZone.toPlannerLocal(start);
    return PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day,
      hour: minute ~/ 60,
      minute: minute % 60,
    );
  }

  List<PlannerAxisMarker> get hourMarkers {
    final raw = <({double elapsedMinutes, String label, String zone})>[];
    for (var elapsed = 0; elapsed < durationMinutes; elapsed += 60) {
      final instant = instantAt(elapsed.toDouble());
      final local = PlannerTimeZone.toPlannerLocal(instant);
      raw.add((
        elapsedMinutes: elapsed.toDouble(),
        label: '${local.hour.toString().padLeft(2, '0')}:00',
        zone: local.timeZoneName,
      ));
    }
    final counts = <String, int>{};
    for (final marker in raw) {
      counts.update(marker.label, (value) => value + 1, ifAbsent: () => 1);
    }
    final markers = [
      for (final marker in raw)
        PlannerAxisMarker(
          elapsedMinutes: marker.elapsedMinutes,
          label: counts[marker.label]! > 1
              ? '${marker.label} ${marker.zone}'
              : marker.label,
        ),
    ];
    markers.add(
      PlannerAxisMarker(
        elapsedMinutes: durationMinutes.toDouble(),
        label: '24:00',
      ),
    );
    return markers;
  }
}

final class PlannerAxisMarker {
  final double elapsedMinutes;
  final String label;

  const PlannerAxisMarker({required this.elapsedMinutes, required this.label});
}
