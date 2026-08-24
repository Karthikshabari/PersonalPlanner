import 'package:freezed_annotation/freezed_annotation.dart';

enum TaskStatus {
  @JsonValue('planned')
  planned('planned'),
  @JsonValue('in_progress')
  inProgress('in_progress'),
  @JsonValue('completed')
  completed('completed'),
  @JsonValue('skipped')
  skipped('skipped'),
  @JsonValue('cancelled')
  cancelled('cancelled'),
  @JsonValue('rescheduled')
  rescheduled('rescheduled');

  const TaskStatus(this.dbValue);

  final String dbValue;

  static TaskStatus fromDb(String value) => TaskStatus.values.firstWhere(
        (s) => s.dbValue == value,
        orElse: () => TaskStatus.planned,
      );

  String get label => switch (this) {
        TaskStatus.planned => 'Planned',
        TaskStatus.inProgress => 'In Progress',
        TaskStatus.completed => 'Completed',
        TaskStatus.skipped => 'Skipped',
        TaskStatus.cancelled => 'Cancelled',
        TaskStatus.rescheduled => 'Rescheduled',
      };

  bool get isTerminal =>
      this == TaskStatus.cancelled || this == TaskStatus.rescheduled;
}
