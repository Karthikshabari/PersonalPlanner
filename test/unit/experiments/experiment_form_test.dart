import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/daos/tag_dao.dart';
import 'package:personal_planner/features/experiments/domain/experiment_form.dart';

TagOptionRow tag(
  String name, {
  bool hasExperiment = false,
  String createdAt = '2026-10-01T00:00:00.000Z',
  String? id,
}) => TagOptionRow(
  id: id ?? 'id-$name',
  name: name,
  createdAt: createdAt,
  hasExperiment: hasExperiment,
);

ExperimentFormState form({
  String name = 'Sketching',
  String start = '2026-10-05',
  String end = '2026-11-03',
  String weekday = '60',
  String weekend = '90',
}) => ExperimentFormState(
  name: name,
  startDate: start,
  endDate: end,
  weekdayTargetText: weekday,
  weekendTargetText: weekend,
);

void main() {
  group('name', () {
    test('empty name disables the button and shows no message', () {
      final v = form(name: '').validate(tags: const []);
      expect(v.canSubmit, isFalse);
      expect(v.infoMessage, isNull);
      expect(v.nameError, isNull);
    });

    test('blank spaces count as empty', () {
      expect(form(name: '   ').validate(tags: const []).canSubmit, isFalse);
    });

    test('a new name says a new tag will be created', () {
      final v = form(name: '  Sketching ').validate(tags: [tag('Learn C')]);
      expect(v.infoMessage, 'A new tag called "Sketching" will be created.');
      expect(v.canSubmit, isTrue);
      expect(v.matchedTag, isNull);
      expect(v.showFirstDateButton, isFalse);
    });

    test('an existing tag matches ignoring case and inner spacing', () {
      for (final typed in ['learn c', 'LEARN C', '  Learn   C  ']) {
        final v = form(name: typed).validate(
          tags: [tag('Learn C')],
          blockCount: 3,
          firstBlockDate: '2026-09-01',
        );
        expect(v.matchedTag?.name, 'Learn C', reason: typed);
      }
    });

    test('existing tag message with several blocks', () {
      final v = form(name: 'learn c').validate(
        tags: [tag('Learn C')],
        blockCount: 12,
        firstBlockDate: '2026-09-01',
      );
      expect(
        v.infoMessage,
        'The tag "Learn C" already exists with 12 blocks. Blocks inside your '
        'dates count straight away.',
      );
      expect(v.showFirstDateButton, isTrue);
      expect(v.canSubmit, isTrue);
    });

    test('existing tag message says "1 block" for one', () {
      final v = form(name: 'Learn C').validate(
        tags: [tag('Learn C')],
        blockCount: 1,
        firstBlockDate: '2026-09-01',
      );
      expect(
        v.infoMessage,
        'The tag "Learn C" already exists with 1 block. Blocks inside your '
        'dates count straight away.',
      );
    });

    test('no first-date button for a tag without blocks', () {
      final v = form(
        name: 'Learn C',
      ).validate(tags: [tag('Learn C')], blockCount: 0, firstBlockDate: null);
      expect(v.infoMessage, contains('already exists with 0 blocks'));
      expect(v.showFirstDateButton, isFalse);
    });

    test('no existing-tag message until the block count is loaded', () {
      final v = form(name: 'Learn C').validate(tags: [tag('Learn C')]);
      expect(v.matchedTag, isNotNull);
      expect(v.infoMessage, isNull);
      expect(v.canSubmit, isTrue);
    });

    test('a tag an experiment already uses is refused', () {
      final v = form(name: 'Learn C').validate(
        tags: [tag('Learn C', hasExperiment: true)],
        blockCount: 5,
        firstBlockDate: '2026-09-01',
      );
      expect(
        v.nameError,
        'An experiment already uses the tag "Learn C". Pick a different name.',
      );
      expect(v.canSubmit, isFalse);
      expect(v.infoMessage, isNull);
      expect(v.showFirstDateButton, isFalse);
    });

    test('with duplicate keys the tag created first decides', () {
      final v = form(name: 'learn c').validate(
        tags: [
          tag('learn c', createdAt: '2026-10-02T00:00:00.000Z', id: 'b'),
          tag(
            'Learn C',
            hasExperiment: true,
            createdAt: '2026-10-01T00:00:00.000Z',
            id: 'a',
          ),
        ],
      );
      expect(v.matchedTag?.id, 'a');
      expect(v.nameError, contains('"Learn C"'));
    });
  });

  group('dates', () {
    test('end before start shows the message and disables the button', () {
      final v = form(
        start: '2026-10-05',
        end: '2026-10-04',
      ).validate(tags: const []);
      expect(
        v.endDateError,
        'The end date must be on or after the start date.',
      );
      expect(v.canSubmit, isFalse);
    });

    test('end equal to start is allowed', () {
      final v = form(
        start: '2026-10-05',
        end: '2026-10-05',
      ).validate(tags: const []);
      expect(v.endDateError, isNull);
      expect(v.canSubmit, isTrue);
    });
  });

  group('targets', () {
    test('an empty or non-numeric target shows the message', () {
      for (final bad in ['', ' ', 'abc', '-1', '1.5', '12345']) {
        final v = form(weekday: bad).validate(tags: const []);
        expect(
          v.targetsError,
          'Targets must be numbers, 0 or more.',
          reason: 'weekday "$bad"',
        );
        expect(v.canSubmit, isFalse);
        final w = form(weekend: bad).validate(tags: const []);
        expect(w.targetsError, isNotNull, reason: 'weekend "$bad"');
      }
    });

    test('0 and 9999 are valid', () {
      final v = form(weekday: '0', weekend: '9999').validate(tags: const []);
      expect(v.targetsError, isNull);
      expect(v.canSubmit, isTrue);
    });

    test('parseExperimentTarget', () {
      expect(parseExperimentTarget('60'), 60);
      expect(parseExperimentTarget(' 7 '), 7);
      expect(parseExperimentTarget('00'), 0);
      expect(parseExperimentTarget(''), isNull);
      expect(parseExperimentTarget('10000'), isNull);
    });
  });

  test('Start experiment is disabled while any error shows', () {
    final v = form(
      name: 'Sketching',
      end: '2026-10-01',
      weekday: '',
    ).validate(tags: const []);
    expect(v.endDateError, isNotNull);
    expect(v.targetsError, isNotNull);
    expect(v.canSubmit, isFalse);
  });
}
