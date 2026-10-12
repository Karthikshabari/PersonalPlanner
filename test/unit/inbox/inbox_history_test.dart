import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/inbox_closure.dart';
import 'package:personal_planner/features/inbox/domain/inbox_history.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 12, 9, 30);
  final t1 = DateTime.utc(2026, 10, 13, 9, 30);
  final t2 = DateTime.utc(2026, 10, 14, 9, 30);

  InboxClosure closed({
    DateTime? at,
    String? reason = 'Bought it elsewhere',
    DateTime? reopenedAt,
  }) => InboxClosure(
    kind: InboxCloseKind.closed,
    at: at ?? t0,
    reason: reason,
    reopenedAt: reopenedAt,
  );

  void expectInvalid(Iterable<InboxClosure> history) {
    expect(
      () => InboxHistory.validate(history),
      throwsA(isA<FormatException>()),
    );
  }

  Map<String, Object?> event({
    String kind = 'closed',
    String at = '2026-10-12T09:30:00.000Z',
    Object? reason = 'Bought it elsewhere',
    Object? experimentId,
    Object? reopenedAt,
    Map<String, Object?> extra = const {},
  }) => {
    'kind': kind,
    'at': at,
    'reason': reason,
    'experiment_id': experimentId,
    'reopened_at': reopenedAt,
    ...extra,
  };

  String json(List<Map<String, Object?>> events) => jsonEncode(events);

  group('decode', () {
    test('the stored example round-trips', () {
      const stored =
          '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z",'
          '"reason":"Bought it elsewhere","experiment_id":null,'
          '"reopened_at":null}]';
      final decoded = InboxHistory.decodeJson(stored);
      expect(decoded.single.kind, InboxCloseKind.closed);
      expect(decoded.single.at, t0);
      expect(decoded.single.reason, 'Bought it elsewhere');
      expect(InboxHistory.encodeJson(decoded), stored);
    });

    test('an empty array is a valid, open history', () {
      expect(InboxHistory.decodeJson('[]'), isEmpty);
      expect(InboxHistory.encodeJson(const []), '[]');
    });

    test('text that is not JSON, or not an array, is refused', () {
      for (final source in ['', 'nope', '{}', '"x"', '3', 'null']) {
        expect(
          () => InboxHistory.decodeJson(source),
          throwsA(isA<FormatException>()),
          reason: source,
        );
      }
    });

    test('an unknown key is refused', () {
      expect(
        () => InboxHistory.decodeJson(
          json([
            event(extra: {'note': 'x'}),
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'a non-object element, wrong value types and a bad kind are refused',
      () {
        final bad = <String>[
          '[1]',
          '["closed"]',
          json([event(kind: 'finished')]),
          json([event(reason: 5)]),
          json([event(experimentId: 5)]),
          json([event(reopenedAt: 5)]),
          json([event(at: 'yesterday')]),
          // An offset instant is not a canonical UTC instant.
          json([event(at: '2026-10-12T09:30:00.000+02:00')]),
        ];
        for (final source in bad) {
          expect(
            () => InboxHistory.decodeJson(source),
            throwsA(isA<FormatException>()),
            reason: source,
          );
        }
      },
    );

    test('more than 100 events are refused', () {
      final events = [
        for (var i = 0; i < 101; i++)
          event(
            at: t0.add(Duration(hours: i)).toIso8601String(),
            reopenedAt: t0
                .add(Duration(hours: i, minutes: 1))
                .toIso8601String(),
          ),
      ];
      expect(
        () => InboxHistory.decodeJson(json(events)),
        throwsA(isA<FormatException>()),
      );
    });

    test('exactly 100 events are accepted', () {
      final events = [
        for (var i = 0; i < 100; i++)
          event(
            at: t0.add(Duration(hours: i)).toIso8601String(),
            reopenedAt: i == 99
                ? null
                : t0.add(Duration(hours: i, minutes: 1)).toIso8601String(),
          ),
      ];
      expect(InboxHistory.decodeJson(json(events)), hasLength(100));
    });
  });

  group('validate', () {
    test('a reason of 200 code points is accepted, 201 is refused', () {
      // The emoji is one code point and two UTF-16 units: the edge is
      // counted in code points, not string length.
      final atEdge = '${'a' * 199}😀';
      expect(atEdge.length, 201);
      expect(atEdge.runes.length, 200);
      InboxHistory.validate([closed(reason: atEdge)]);
      expectInvalid([closed(reason: '${atEdge}b')]);
    });

    test('a blank or untrimmed reason is refused', () {
      expectInvalid([closed(reason: '')]);
      expectInvalid([closed(reason: '   ')]);
      expectInvalid([closed(reason: ' padded ')]);
    });

    test('closed needs a reason; let go may have one or none', () {
      expectInvalid([closed(reason: null)]);
      InboxHistory.validate([InboxClosure(kind: InboxCloseKind.letGo, at: t0)]);
      InboxHistory.validate([
        InboxClosure(kind: InboxCloseKind.letGo, at: t0, reason: 'Not now'),
      ]);
      // An optional reason that is present must still be non-blank.
      expectInvalid([
        InboxClosure(kind: InboxCloseKind.letGo, at: t0, reason: ' '),
      ]);
    });

    test('an experiment event has an id and no reason', () {
      InboxHistory.validate([
        InboxClosure(
          kind: InboxCloseKind.experiment,
          at: t0,
          experimentId: 'experiment:tag-1',
        ),
      ]);
      expectInvalid([
        InboxClosure(
          kind: InboxCloseKind.experiment,
          at: t0,
          reason: 'why',
          experimentId: 'experiment:tag-1',
        ),
      ]);
      expectInvalid([InboxClosure(kind: InboxCloseKind.experiment, at: t0)]);
      expectInvalid([
        InboxClosure(
          kind: InboxCloseKind.experiment,
          at: t0,
          experimentId: '  ',
        ),
      ]);
    });

    test('an experiment id on closed or let go is refused', () {
      expectInvalid([
        InboxClosure(
          kind: InboxCloseKind.closed,
          at: t0,
          reason: 'r',
          experimentId: 'experiment:tag-1',
        ),
      ]);
      expectInvalid([
        InboxClosure(
          kind: InboxCloseKind.letGo,
          at: t0,
          experimentId: 'experiment:tag-1',
        ),
      ]);
    });

    test('only the last event may be still closed', () {
      expectInvalid([closed(at: t0), closed(at: t1)]);
      InboxHistory.validate([closed(at: t0, reopenedAt: t1), closed(at: t1)]);
    });

    test('events must be ordered by time', () {
      expectInvalid([closed(at: t1, reopenedAt: t2), closed(at: t0)]);
      // Equal instants are not out of order.
      InboxHistory.validate([closed(at: t0, reopenedAt: t0), closed(at: t0)]);
    });

    test('a bring back cannot precede its close', () {
      expectInvalid([closed(at: t1, reopenedAt: t0)]);
      InboxHistory.validate([closed(at: t0, reopenedAt: t0)]);
    });

    test('timestamps must be UTC', () {
      expectInvalid([closed(at: DateTime(2026, 10, 12, 9, 30))]);
      expectInvalid([closed(at: t0, reopenedAt: DateTime(2026, 10, 13))]);
    });
  });

  group('helpers', () {
    test('isClosed, openClosure and lastReopenedAt', () {
      expect(InboxHistory.isClosed(const []), isFalse);
      expect(InboxHistory.openClosure(const []), isNull);
      expect(InboxHistory.lastReopenedAt(const []), isNull);

      final open = [closed()];
      expect(InboxHistory.isClosed(open), isTrue);
      expect(InboxHistory.openClosure(open), open.single);
      expect(InboxHistory.lastReopenedAt(open), isNull);

      final reopened = [closed(reopenedAt: t1)];
      expect(InboxHistory.isClosed(reopened), isFalse);
      expect(InboxHistory.openClosure(reopened), isNull);
      expect(InboxHistory.lastReopenedAt(reopened), t1);

      final again = [closed(at: t0, reopenedAt: t1), closed(at: t1)];
      expect(InboxHistory.isClosed(again), isTrue);
      // The most recent Bring back still counts while closed again.
      expect(InboxHistory.lastReopenedAt(again), t1);
    });

    test('close trims, appends and refuses a second close', () {
      final first = InboxHistory.close(
        const [],
        kind: InboxCloseKind.closed,
        at: t0,
        reason: '  Bought it elsewhere  ',
      );
      expect(first.single.reason, 'Bought it elsewhere');
      expect(
        () => InboxHistory.close(first, kind: InboxCloseKind.letGo, at: t1),
        throwsStateError,
      );
    });

    test(
      'close refuses a missing reason for closed and keeps let go empty',
      () {
        expect(
          () => InboxHistory.close(
            const [],
            kind: InboxCloseKind.closed,
            at: t0,
            reason: '   ',
          ),
          throwsA(isA<FormatException>()),
        );
        final letGo = InboxHistory.close(
          const [],
          kind: InboxCloseKind.letGo,
          at: t0,
          reason: '  ',
        );
        expect(letGo.single.reason, isNull);
      },
    );

    test(
      'reopen keeps the event, sets reopened_at and allows closing again',
      () {
        final closedOnce = InboxHistory.close(
          const [],
          kind: InboxCloseKind.closed,
          at: t0,
          reason: 'Not needed',
        );
        final reopened = InboxHistory.reopen(closedOnce, t1);
        expect(reopened, hasLength(1));
        expect(reopened.single.reason, 'Not needed');
        expect(reopened.single.reopenedAt, t1);
        expect(
          () => InboxHistory.reopen(reopened, t2),
          throwsStateError,
          reason: 'only a closed idea can be brought back',
        );
        final closedAgain = InboxHistory.close(
          reopened,
          kind: InboxCloseKind.letGo,
          at: t2,
        );
        expect(closedAgain, hasLength(2));
        expect(InboxHistory.isClosed(closedAgain), isTrue);
      },
    );

    test('reopen before the close instant is refused', () {
      final closedOnce = InboxHistory.close(
        const [],
        kind: InboxCloseKind.closed,
        at: t1,
        reason: 'r',
      );
      expect(
        () => InboxHistory.reopen(closedOnce, t0),
        throwsA(isA<FormatException>()),
      );
    });

    test('a 100-event history cannot take one more close', () {
      var history = <InboxClosure>[];
      for (var i = 0; i < 100; i++) {
        history = InboxHistory.close(
          history,
          kind: InboxCloseKind.letGo,
          at: t0.add(Duration(hours: i)),
        );
        if (i < 99) {
          history = InboxHistory.reopen(
            history,
            t0.add(Duration(hours: i, minutes: 1)),
          );
        }
      }
      history = InboxHistory.reopen(history, t0.add(const Duration(days: 30)));
      expect(
        () => InboxHistory.close(
          history,
          kind: InboxCloseKind.letGo,
          at: t0.add(const Duration(days: 31)),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
