import 'package:freezed_annotation/freezed_annotation.dart';

import 'task.dart';

part 'inbox_item.freezed.dart';

/// An entry in the Inbox UI. Architecture.md §3: overdue tasks are NOT moved
/// into the inbox — they stay scheduled rows and are surfaced query-side, so
/// the union keeps the two cases distinguishable (scheduling an explicit
/// inbox item is a simple update; rescheduling an overdue task creates a
/// linked copy).
@freezed
sealed class InboxItem with _$InboxItem {
  const factory InboxItem.explicit(Task task) = ExplicitInboxItem;

  const factory InboxItem.overdue(Task task) = OverdueInboxItem;

  const InboxItem._();

  @override
  Task get task => switch (this) {
        ExplicitInboxItem(:final task) => task,
        OverdueInboxItem(:final task) => task,
      };

  bool get isOverdue => this is OverdueInboxItem;

  /// A deterministic, short presentation value. The stored capture remains
  /// the complete task description; this getter never writes or normalizes it.
  String get displayPreview {
    if (isOverdue) return task.title;
    final content = task.description ?? '';
    final firstLine = content
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    return firstLine.trim().isEmpty ? 'Inbox capture' : firstLine.trim();
  }
}
