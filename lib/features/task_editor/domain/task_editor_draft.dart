import '../../../core/models/task.dart';
import '../../../core/models/enums/priority.dart';
import '../../../core/models/enums/task_status.dart';

/// The complete persisted state that an editor Save accepts as its new
/// baseline.  It deliberately contains the task and staged tag membership;
/// the editor keeps recurrence configuration alongside the task because the
/// existing recurrence aggregate owns that write.
class TaskEditorPersistedState {
  final Task task;
  final Set<String> tagIds;
  final String? recurrenceSignature;

  TaskEditorPersistedState({
    required this.task,
    required Set<String> tagIds,
    this.recurrenceSignature,
  }) : tagIds = Set.unmodifiable(tagIds);
}

/// A normalized snapshot used for dirty-state comparison.  This is editor
/// memory only; it is never serialized or synchronized.
class TaskEditorBaseline {
  final Task task;
  final Set<String> tagIds;
  final String? recurrenceSignature;

  TaskEditorBaseline({
    required this.task,
    required Set<String> tagIds,
    this.recurrenceSignature,
  }) : tagIds = Set.unmodifiable(tagIds);

  TaskEditorBaseline copyWith({
    Task? task,
    Set<String>? tagIds,
    String? recurrenceSignature,
  }) => TaskEditorBaseline(
    task: task ?? this.task,
    tagIds: tagIds ?? this.tagIds,
    recurrenceSignature: recurrenceSignature ?? this.recurrenceSignature,
  );

  static String normalizeTitle(String value) => value.trim();

  static String? normalizeDescription(String value) =>
      value.isEmpty ? null : value;

  static String? normalizeNotes(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool hasSameTags(Set<String> ids) =>
      tagIds.length == ids.length && tagIds.containsAll(ids);

  bool hasSameTaskValues(Task other) {
    final leftDescription = task.description;
    final rightDescription = other.description;
    return normalizeTitle(task.title) == normalizeTitle(other.title) &&
        leftDescription == rightDescription &&
        normalizeNotes(task.notes ?? '') == normalizeNotes(other.notes ?? '') &&
        task.categoryId == other.categoryId &&
        task.priority == other.priority &&
        task.status == other.status &&
        task.startTime == other.startTime &&
        task.endTime == other.endTime &&
        task.actualDurationMin == other.actualDurationMin &&
        task.recurringRuleId == other.recurringRuleId &&
        task.dueDate == other.dueDate;
  }
}

/// Pure field-level editor state and merge rules.
///
/// The widget owns controllers and user prompts; this object owns the
/// deterministic rule that a draft changes only fields the user edited,
/// preserving unrelated writes made after the editor opened.
class TaskEditorDraft {
  final String title;
  final String? description;
  final String? notes;
  final String? categoryId;
  final Priority priority;
  final TaskStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? dueDate;

  final int? actualDurationMin;
  final bool actualDurationDirty;

  const TaskEditorDraft({
    required this.title,
    required this.description,
    required this.notes,
    required this.categoryId,
    required this.priority,
    required this.status,
    required this.startTime,
    required this.endTime,
    this.dueDate,
    required this.actualDurationMin,
    required this.actualDurationDirty,
  });

  /// Labels for fields changed both locally and remotely to different values.
  List<String> conflictingFields(Task baseline, Task latest) {
    final result = <String>[];
    void check<T>(String label, T local, T base, T remote) {
      if (local != base && remote != base && local != remote) {
        result.add(label);
      }
    }

    // Title intent is semantic rather than formatting-only. The R14 history
    // decision likewise trims both sides, so a trailing-space cleanup must
    // not turn a concurrent title change into a false three-way conflict.
    check(
      'Title',
      TaskEditorBaseline.normalizeTitle(title),
      TaskEditorBaseline.normalizeTitle(baseline.title),
      TaskEditorBaseline.normalizeTitle(latest.title),
    );
    check('Description', description, baseline.description, latest.description);
    check('Notes', notes, baseline.notes, latest.notes);
    check('Category', categoryId, baseline.categoryId, latest.categoryId);
    check('Priority', priority, baseline.priority, latest.priority);
    check('Status', status, baseline.status, latest.status);
    check('Start time', startTime, baseline.startTime, latest.startTime);
    check('End time', endTime, baseline.endTime, latest.endTime);
    check('Due date', dueDate, baseline.dueDate, latest.dueDate);
    if (actualDurationDirty) {
      check(
        'Actual duration',
        actualDurationMin,
        baseline.actualDurationMin,
        latest.actualDurationMin,
      );
    }
    return result;
  }

  /// Applies locally changed fields over [latest], preserving fields that
  /// were untouched by this draft even when [latest] changed remotely.
  Task mergeOnto(Task baseline, Task latest) {
    T choose<T>(T local, T base, T remote) => local != base ? local : remote;
    return latest.copyWith(
      // Keep a newer persisted spelling when the draft has no normalized
      // title change. This is important while a Save prompt is open: the
      // subsequent R14 comparison must use the actual row being overwritten.
      title:
          TaskEditorBaseline.normalizeTitle(title) !=
              TaskEditorBaseline.normalizeTitle(baseline.title)
          ? title
          : latest.title,
      description: choose(
        description,
        baseline.description,
        latest.description,
      ),
      notes: choose(notes, baseline.notes, latest.notes),
      categoryId: choose(categoryId, baseline.categoryId, latest.categoryId),
      priority: choose(priority, baseline.priority, latest.priority),
      status: choose(status, baseline.status, latest.status),
      startTime: choose(startTime, baseline.startTime, latest.startTime),
      endTime: choose(endTime, baseline.endTime, latest.endTime),
      dueDate: choose(dueDate, baseline.dueDate, latest.dueDate),
      actualDurationMin: actualDurationDirty
          ? actualDurationMin
          : latest.actualDurationMin,
    );
  }
}
