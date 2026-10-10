import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/features/experiments/domain/experiment_target_changes.dart';

import '../../helpers/experiment_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

ExperimentTargetChange change(
  String week,
  int weekday,
  int weekend, [
  String madeOn = '2026-10-10',
]) => ExperimentTargetChange(
  effectiveWeekStart: week,
  weekdayTargetMin: weekday,
  weekendTargetMin: weekend,
  madeOn: madeOn,
);

Map<String, Object?> item({
  Object? week = '2026-10-05',
  Object? weekday = 75,
  Object? weekend = 90,
  Object? madeOn = '2026-10-10',
}) => {
  'effective_week_start': week,
  'weekday_target_min': weekday,
  'weekend_target_min': weekend,
  'made_on': madeOn,
};

String json(List<Object?> items) => jsonEncode(items);

void main() {
  setupSqliteForTests();

  final rejected = throwsA(isA<FormatException>());

  group('decodeTargetChangesJson', () {
    test('decodes an empty array and valid entries', () {
      expect(decodeTargetChangesJson('[]'), isEmpty);
      final decoded = decodeTargetChangesJson(
        json([item(), item(week: '2026-10-12', weekday: 60, weekend: 15)]),
      );
      expect(decoded, [
        change('2026-10-05', 75, 90),
        change('2026-10-12', 60, 15),
      ]);
    });

    test('accepts the limits 15 and 240', () {
      expect(
        decodeTargetChangesJson(json([item(weekday: 15, weekend: 240)])),
        hasLength(1),
      );
    });

    test('rejects text that is not a JSON array', () {
      expect(() => decodeTargetChangesJson('not json'), rejected);
      expect(() => decodeTargetChangesJson('{}'), rejected);
      expect(() => decodeTargetChangesJson('"[]"'), rejected);
      expect(() => decodeTargetChangesJson('null'), rejected);
    });

    test('rejects an item that is not an object with exactly four keys', () {
      expect(() => decodeTargetChangesJson('[1]'), rejected);
      expect(() => decodeTargetChangesJson('[[]]'), rejected);
      expect(() => decodeTargetChangesJson('[{}]'), rejected);
      expect(
        () => decodeTargetChangesJson(json([item()..['extra'] = 1])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item()..remove('made_on')])),
        rejected,
      );
      final renamed = item()..remove('made_on');
      renamed['made_at'] = '2026-10-10';
      expect(() => decodeTargetChangesJson(json([renamed])), rejected);
    });

    test('rejects wrong value types, including a num that is not an int', () {
      expect(() => decodeTargetChangesJson(json([item(week: 5)])), rejected);
      expect(() => decodeTargetChangesJson(json([item(madeOn: 5)])), rejected);
      expect(
        () => decodeTargetChangesJson(json([item(weekday: '75')])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item(weekend: null)])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item(weekday: 75.5)])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(
          '[{"effective_week_start":"2026-10-05","weekday_target_min":75.0,'
          '"weekend_target_min":90,"made_on":"2026-10-10"}]',
        ),
        rejected,
      );
    });

    test('rejects a bad date and a week that is not a Monday', () {
      expect(
        () => decodeTargetChangesJson(json([item(week: '2026-02-30')])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item(week: '2026-1-5')])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item(madeOn: '2026-13-01')])),
        rejected,
      );
      // 2026-10-06 is a Tuesday and 2026-10-04 a Sunday.
      expect(
        () => decodeTargetChangesJson(json([item(week: '2026-10-06')])),
        rejected,
      );
      expect(
        () => decodeTargetChangesJson(json([item(week: '2026-10-04')])),
        rejected,
      );
    });

    test('rejects a target outside 15..240', () {
      for (final bad in [0, 10, 14, 241, 9999, -15]) {
        expect(
          () => decodeTargetChangesJson(json([item(weekday: bad)])),
          rejected,
          reason: 'weekday $bad',
        );
        expect(
          () => decodeTargetChangesJson(json([item(weekend: bad)])),
          rejected,
          reason: 'weekend $bad',
        );
      }
    });

    test('rejects duplicate and descending weeks', () {
      expect(() => decodeTargetChangesJson(json([item(), item()])), rejected);
      expect(
        () => decodeTargetChangesJson(
          json([item(week: '2026-10-12'), item(week: '2026-10-05')]),
        ),
        rejected,
      );
    });
  });

  group('encodeTargetChangesJson and validateTargetChanges', () {
    test('encode writes the four keys in order and round-trips', () {
      final changes = [
        change('2026-10-05', 75, 90),
        change('2026-10-12', 60, 90),
      ];
      final text = encodeTargetChangesJson(changes);
      expect(
        text,
        '[{"effective_week_start":"2026-10-05","weekday_target_min":75,'
        '"weekend_target_min":90,"made_on":"2026-10-10"},'
        '{"effective_week_start":"2026-10-12","weekday_target_min":60,'
        '"weekend_target_min":90,"made_on":"2026-10-10"}]',
      );
      expect(decodeTargetChangesJson(text), changes);
      expect(encodeTargetChangesJson(const []), '[]');
    });

    test('validate accepts good lists and rejects each rule', () {
      validateTargetChanges(const []);
      validateTargetChanges([change('2026-10-05', 15, 240)]);
      expect(
        () => validateTargetChanges([change('2026-10-06', 75, 90)]),
        rejected,
      );
      expect(
        () => validateTargetChanges([change('2026-10-05', 10, 90)]),
        rejected,
      );
      expect(
        () => validateTargetChanges([change('2026-10-05', 75, 241)]),
        rejected,
      );
      expect(() => validateTargetChanges([change('bad', 75, 90)]), rejected);
      expect(
        () => validateTargetChanges([
          change('2026-10-05', 75, 90),
          change('2026-10-05', 80, 90),
        ]),
        rejected,
      );
      expect(
        () => validateTargetChanges([
          change('2026-10-12', 75, 90),
          change('2026-10-05', 80, 90),
        ]),
        rejected,
      );
    });
  });

  group('keptTargetsForWeek and keptPendingTargetChange', () {
    final base = testKeptExperiment(
      targetChanges: [
        change('2026-09-14', 75, 90),
        change('2026-10-05', 90, 105),
        change('2026-10-19', 45, 60),
      ],
    );

    test('falls back to the experiment targets before any change', () {
      expect(keptTargetsForWeek(base, '2026-09-07'), (
        weekdayMin: 60,
        weekendMin: 90,
      ));
      expect(keptTargetsForWeek(testKeptExperiment(), '2026-10-05'), (
        weekdayMin: 60,
        weekendMin: 90,
      ));
    });

    test('uses the change with the greatest week at or before the week', () {
      expect(keptTargetsForWeek(base, '2026-09-14'), (
        weekdayMin: 75,
        weekendMin: 90,
      ));
      expect(keptTargetsForWeek(base, '2026-09-28'), (
        weekdayMin: 75,
        weekendMin: 90,
      ));
      expect(keptTargetsForWeek(base, '2026-10-05'), (
        weekdayMin: 90,
        weekendMin: 105,
      ));
      expect(keptTargetsForWeek(base, '2026-10-12'), (
        weekdayMin: 90,
        weekendMin: 105,
      ));
      expect(keptTargetsForWeek(base, '2026-11-02'), (
        weekdayMin: 45,
        weekendMin: 60,
      ));
    });

    test('the pending change is the first one after the current week', () {
      expect(
        keptPendingTargetChange(base, '2026-10-05'),
        change('2026-10-19', 45, 60),
      );
      expect(
        keptPendingTargetChange(base, '2026-09-07'),
        change('2026-09-14', 75, 90),
      );
      expect(keptPendingTargetChange(base, '2026-10-19'), isNull);
      expect(
        keptPendingTargetChange(testKeptExperiment(), '2026-10-05'),
        isNull,
      );
    });
  });

  group('applyKeptTargetChange', () {
    final e = testKeptExperiment();
    const thisWeek = '2026-10-05';

    List<ExperimentTargetChange> apply(
      Experiment experiment,
      int weekday,
      int weekend, {
      required bool fromNextWeek,
    }) => applyKeptTargetChange(
      experiment: experiment,
      draft: (weekdayMin: weekday, weekendMin: weekend),
      fromNextWeek: fromNextWeek,
      currentWeekStart: thisWeek,
      madeOn: '2026-10-10',
    );

    test('V4a: from this week writes one current entry', () {
      expect(apply(e, 75, 90, fromNextWeek: false), [
        change('2026-10-05', 75, 90),
      ]);
    });

    test('V4b: from next week writes one pending entry', () {
      final result = apply(e, 75, 90, fromNextWeek: true);
      expect(result, [change('2026-10-12', 75, 90)]);
      final withPending = e.copyWith(targetChanges: result);
      expect(keptPendingTargetChange(withPending, thisWeek), result.single);
      expect(keptTargetsForWeek(withPending, thisWeek), (
        weekdayMin: 60,
        weekendMin: 90,
      ));
    });

    test('V4c: the old values from next week remove the pending entry', () {
      final pending = e.copyWith(
        targetChanges: apply(e, 75, 90, fromNextWeek: true),
      );
      expect(apply(pending, 60, 90, fromNextWeek: true), isEmpty);
    });

    test('from this week replaces an entry of the same week', () {
      final same = e.copyWith(targetChanges: [change('2026-10-05', 75, 90)]);
      expect(apply(same, 90, 90, fromNextWeek: false), [
        change('2026-10-05', 90, 90),
      ]);
    });

    test('from this week also removes a pending entry', () {
      final both = e.copyWith(
        targetChanges: [
          change('2026-10-05', 75, 90),
          change('2026-10-12', 100, 90),
        ],
      );
      expect(apply(both, 80, 90, fromNextWeek: false), [
        change('2026-10-05', 80, 90),
      ]);
    });

    test('from this week with the previous values removes the week entry', () {
      final history = e.copyWith(
        targetChanges: [
          change('2026-09-28', 75, 90),
          change('2026-10-05', 90, 90),
        ],
      );
      expect(apply(history, 75, 90, fromNextWeek: false), [
        change('2026-09-28', 75, 90),
      ]);
      final single = e.copyWith(targetChanges: [change('2026-10-05', 75, 90)]);
      expect(apply(single, 60, 90, fromNextWeek: false), isEmpty);
    });

    test('earlier weeks are never rewritten', () {
      final history = e.copyWith(
        targetChanges: [change('2026-09-21', 45, 60, '2026-09-20')],
      );
      final result = apply(history, 75, 90, fromNextWeek: false);
      expect(result, [
        change('2026-09-21', 45, 60, '2026-09-20'),
        change('2026-10-05', 75, 90),
      ]);
    });
  });

  test('V6: steppers and clamp', () {
    expect(keptStepDown(15), 15);
    expect(keptStepUp(240), 240);
    expect(keptStepUp(75), 90);
    expect(keptStepDown(90), 75);
    expect(keptClampTarget(0), 15);
    expect(keptClampTarget(300), 240);
    expect(keptClampTarget(100), 100);
  });
}
