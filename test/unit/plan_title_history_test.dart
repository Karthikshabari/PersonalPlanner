import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/features/task_editor/domain/plan_title_history.dart';

void main() {
  final at = DateTime.utc(2026, 9, 13, 10);
  PlanTitleChange event({
    String id = '11111111-1111-4111-8111-111111111111',
    String previous = 'Read book',
    String next = 'Office work',
    DateTime? changedAt,
    DateTime? revertedAt,
  }) => PlanTitleChange(
    id: id,
    previousTitle: previous,
    newTitle: next,
    changedAt: changedAt ?? at,
    revertedAt: revertedAt,
  );

  test(
    'normalizes title comparisons without changing case or interior text',
    () {
      expect(PlanTitleHistory.normalizeTitle('  Read  book  '), 'Read  book');
      expect(PlanTitleHistory.normalizeTitle('Read'), isNot('read'));
    },
  );

  test('append restores the same stable event ID for a redo', () {
    final original = event();
    final reverted = original.copyWith(
      revertedAt: at.add(const Duration(hours: 1)),
    );

    final restored = PlanTitleHistory.appendOrRestore([reverted], original);

    expect(restored, hasLength(1));
    expect(restored.single.id, original.id);
    expect(restored.single.revertedAt, isNull);
  });

  test('union keeps unique history and rejects an immutable ID collision', () {
    final first = event();
    final second = event(
      id: '22222222-2222-4222-8222-222222222222',
      previous: 'Office work',
      next: 'Client call',
      changedAt: at.add(const Duration(hours: 1)),
    );
    expect(
      PlanTitleHistory.union(chosen: [first], other: [second]),
      orderedEquals([first, second]),
    );
    expect(
      () => PlanTitleHistory.union(
        chosen: [first],
        other: [first.copyWith(newTitle: 'Different')],
      ),
      throwsFormatException,
    );
  });

  test('selected event must be live and describe the current title', () {
    final change = event();
    PlanTitleHistory.validate(
      [change],
      displayPlanChangeId: change.id,
      currentTitle: 'Office work',
    );
    expect(
      () => PlanTitleHistory.validate(
        [change],
        displayPlanChangeId: change.id,
        currentTitle: 'Client call',
      ),
      throwsFormatException,
    );
  });

  test('malformed JSON is rejected before it can become a Task', () {
    expect(
      () => PlanTitleHistory.decodeJson('{"id":"not-an-array"}'),
      throwsFormatException,
    );
  });

  test('existing event bodies cannot be removed or repurposed', () {
    final original = event();
    expect(
      () => PlanTitleHistory.validateTransition(
        previous: [original],
        next: const [],
      ),
      throwsFormatException,
    );
    expect(
      () => PlanTitleHistory.validateTransition(
        previous: [original],
        next: [original.copyWith(newTitle: 'Repurposed')],
      ),
      throwsFormatException,
    );
    PlanTitleHistory.validateTransition(
      previous: [original],
      next: [original.copyWith(revertedAt: at.add(const Duration(hours: 1)))],
    );
  });

  test('event JSON rejects unknown fields and non-string timestamp values', () {
    expect(
      () => PlanTitleHistory.decodeJson('''
        [{"id":"11111111-1111-4111-8111-111111111111", "previous_title":"Read book", "new_title":"Office work", "changed_at":"2026-09-13T10:00:00.000Z", "reverted_at":null, "unexpected":true}]
      '''),
      throwsFormatException,
    );
    expect(
      () => PlanTitleHistory.decodeJson('''
        [{"id":"11111111-1111-4111-8111-111111111111", "previous_title":"Read book", "new_title":"Office work", "changed_at":123, "reverted_at":null}]
      '''),
      throwsFormatException,
    );
  });
}
