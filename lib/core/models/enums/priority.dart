/// Legacy task priority (UAT F-010): there is no priority UI. The value is
/// kept only so stored, synced and backed-up rows round-trip unchanged.
enum Priority {
  none,
  low,
  medium,
  high,
  urgent;

  int get dbValue => index;

  static Priority fromDb(int value) => Priority.values.firstWhere(
    (p) => p.index == value.clamp(0, 4),
    orElse: () => Priority.none,
  );

  @Deprecated('UAT F-010: priority has no UI; retired at the code level.')
  String get label => switch (this) {
    Priority.none => 'None',
    Priority.low => 'Low',
    Priority.medium => 'Medium',
    Priority.high => 'High',
    Priority.urgent => 'Urgent',
  };
}
