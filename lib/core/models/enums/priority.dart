enum Priority {
  none,
  low,
  medium,
  high,
  urgent;

  int get dbValue => index;

  static Priority fromDb(int value) =>
      Priority.values.firstWhere((p) => p.index == value.clamp(0, 4),
          orElse: () => Priority.none);

  String get label => switch (this) {
        Priority.none => 'None',
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
        Priority.urgent => 'Urgent',
      };
}
