import 'package:flutter/foundation.dart';

/// Ephemeral input for creating or scheduling a task.  The ID belongs to the
/// form session, so validation failures and retries never create a second
/// task identity.
@immutable
class ScheduledTaskDraft {
  static const Object _unset = Object();

  final String id;
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;

  const ScheduledTaskDraft({
    required this.id,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  DateTime? get startTime => start;
  DateTime? get endTime => end;

  String? get validationError {
    if (title.trim().isEmpty) return 'Title must not be blank';
    if (start == null) return 'Start date and time are required';
    if (end == null) return 'End date and time are required';
    if (!end!.isAfter(start!)) return 'End must be later than start';
    return null;
  }

  bool get isValid => validationError == null;

  ScheduledTaskDraft copyWith({
    String? id,
    String? title,
    String? description,
    Object? start = _unset,
    Object? end = _unset,
  }) => ScheduledTaskDraft(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    start: identical(start, _unset) ? this.start : start as DateTime?,
    end: identical(end, _unset) ? this.end : end as DateTime?,
  );
}
