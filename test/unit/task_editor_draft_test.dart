import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/priority.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/task_editor/domain/task_editor_draft.dart';

void main() {
  final base = Task(
    id: 'draft-task',
    title: 'Original',
    description: 'Original description',
    notes: 'Original notes',
    priority: Priority.none,
    status: TaskStatus.planned,
    estimatedDurationMin: 30,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('merge preserves unrelated remote fields', () {
    final draft = TaskEditorDraft(
      title: 'Local title',
      description: base.description,
      notes: base.notes,
      categoryId: base.categoryId,
      priority: base.priority,
      status: base.status,
      startTime: base.startTime,
      endTime: base.endTime,
      actualDurationMin: base.actualDurationMin,
      actualDurationDirty: false,
    );
    final latest = base.copyWith(notes: 'Remote notes');
    final merged = draft.mergeOnto(base, latest);

    expect(merged.title, 'Local title');
    expect(merged.notes, 'Remote notes');
    expect(draft.conflictingFields(base, latest), isEmpty);
  });

  test('reports only fields changed on both sides to different values', () {
    final draft = TaskEditorDraft(
      title: 'Local title',
      description: base.description,
      notes: base.notes,
      categoryId: base.categoryId,
      priority: base.priority,
      status: base.status,
      startTime: base.startTime,
      endTime: base.endTime,
      actualDurationMin: base.actualDurationMin,
      actualDurationDirty: false,
    );
    final latest = base.copyWith(title: 'Remote title');

    expect(draft.conflictingFields(base, latest), ['Title']);
  });

  test('trim-only title input is not a title conflict or local overwrite', () {
    final draft = TaskEditorDraft(
      title: 'Original',
      description: base.description,
      notes: base.notes,
      categoryId: base.categoryId,
      priority: base.priority,
      status: base.status,
      startTime: base.startTime,
      endTime: base.endTime,
      actualDurationMin: base.actualDurationMin,
      actualDurationDirty: false,
    );
    final latest = base.copyWith(title: '  Original  ');

    expect(draft.conflictingFields(base, latest), isEmpty);
    expect(draft.mergeOnto(base, latest).title, '  Original  ');
  });

  test('baseline normalization matches persisted editor semantics', () {
    expect(TaskEditorBaseline.normalizeTitle('  Original  '), 'Original');
    expect(
      TaskEditorBaseline.normalizeDescription('  keep surrounding spaces  '),
      '  keep surrounding spaces  ',
    );
    expect(TaskEditorBaseline.normalizeDescription(''), isNull);
    expect(TaskEditorBaseline.normalizeNotes('  '), isNull);
    expect(TaskEditorBaseline.normalizeNotes('  note  '), 'note');
  });

  test('baseline compares all persisted task fields and tags', () {
    final baseline = TaskEditorBaseline(task: base, tagIds: {'work', 'focus'});

    expect(
      baseline.hasSameTaskValues(base.copyWith(title: '  Original  ')),
      isTrue,
    );
    expect(
      baseline.hasSameTaskValues(base.copyWith(notes: 'changed')),
      isFalse,
    );
    expect(baseline.hasSameTags({'focus', 'work'}), isTrue);
    expect(baseline.hasSameTags({'work'}), isFalse);
  });

  test('due date participates in dirty merge and conflicts', () {
    final local = TaskEditorDraft(
      title: base.title,
      description: base.description,
      notes: base.notes,
      categoryId: base.categoryId,
      priority: base.priority,
      status: base.status,
      startTime: base.startTime,
      endTime: base.endTime,
      dueDate: '2026-09-12',
      actualDurationMin: base.actualDurationMin,
      actualDurationDirty: false,
    );
    final remote = base.copyWith(dueDate: '2026-09-13');
    expect(local.conflictingFields(base, remote), ['Due date']);
    expect(local.mergeOnto(base, base).dueDate, '2026-09-12');
  });
}
