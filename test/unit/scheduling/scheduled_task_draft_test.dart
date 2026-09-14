import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/timeline/domain/scheduled_task_draft.dart';

void main() {
  final start = DateTime.utc(2026, 9, 11, 23, 30);
  final end = DateTime.utc(2026, 9, 12, 0, 30);

  test('validates title and complete positive intervals', () {
    expect(
      ScheduledTaskDraft(
        id: 'draft-1',
        title: 'Night work',
        description: 'Details',
        start: start,
        end: end,
      ).isValid,
      isTrue,
    );
    expect(
      ScheduledTaskDraft(
        id: 'draft-1',
        title: ' ',
        description: '',
        start: start,
        end: end,
      ).validationError,
      'Title must not be blank',
    );
  });

  test('rejects incomplete, equal and reversed intervals', () {
    ScheduledTaskDraft draft(DateTime? draftStart, DateTime? draftEnd) =>
        ScheduledTaskDraft(
          id: 'draft-1',
          title: 'Task',
          description: '',
          start: draftStart,
          end: draftEnd,
        );

    expect(draft(null, end).isValid, isFalse);
    expect(draft(start, null).isValid, isFalse);
    expect(draft(start, start).isValid, isFalse);
    expect(draft(end, start).isValid, isFalse);
  });

  test('copyWith can clear either endpoint without changing the stable ID', () {
    final draft = ScheduledTaskDraft(
      id: 'draft-1',
      title: 'Task',
      description: '',
      start: start,
      end: end,
    );
    final cleared = draft.copyWith(start: null, end: null);
    expect(cleared.id, draft.id);
    expect(cleared.start, isNull);
    expect(cleared.end, isNull);
  });
}
