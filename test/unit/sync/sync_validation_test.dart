import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';

SyncRemoteChange _change(
  String table,
  Map<String, dynamic> payload, {
  String operation = 'update',
}) => SyncRemoteChange(
  changeId: 1,
  operationId: 'operation-1',
  tableName: table,
  recordId: payload['id']?.toString() ?? 'rule-1',
  operation: operation,
  serverVersion: 1,
  serverTimestamp: DateTime.utc(2026, 1, 1),
  payload: payload,
);

Map<String, dynamic> _taskPayload() => {
  'id': 'task-1',
  'title': 'Plan',
  'status': 'planned',
  'priority': 1,
  'is_inbox': 0,
  'start_time': '2026-01-01T09:00:00Z',
  'end_time': '2026-01-01T10:00:00Z',
  'created_at': '2026-01-01T08:00:00Z',
  'updated_at': '2026-01-01T08:00:00Z',
  'deleted_at': null,
};

Map<String, dynamic> _recurrencePayload() => {
  'id': 'rule-1',
  'rrule': 'FREQ=DAILY',
  'task_title': 'Daily plan',
  'duration_min': 30,
  'priority': 1,
  'category_id': null,
  'tags_json': '["planning"]',
  'start_time_of_day': '09:00',
  'start_date': '2026-01-01',
  'end_date': null,
  'is_active': 1,
  'exceptions_json': '["2026-01-02"]',
  'created_at': '2026-01-01T08:00:00Z',
  'updated_at': '2026-01-01T08:00:00Z',
  'deleted_at': null,
};

Map<String, dynamic> _dayContextPayload({
  String date = '2026-01-02',
  String kind = 'travel',
  Object? customLabel,
}) => {
  'id': generateDeterministicUuid('day-context:$date'),
  'date': date,
  'kind': kind,
  'custom_label': customLabel,
  'created_at': '2026-01-01T08:00:00Z',
  'updated_at': '2026-01-01T08:00:00Z',
  'deleted_at': null,
};

void main() {
  test(
    'rejects malformed optional timestamps instead of treating them as null',
    () {
      final payload = _taskPayload()..['start_time'] = 'not-a-timestamp';

      expect(
        () => SyncPayloadValidator.validate(_change('tasks', payload)),
        throwsA(isA<SyncValidationException>()),
      );
    },
  );

  test('rejects fractional integer values', () {
    final payload = _taskPayload()..['priority'] = 1.5;

    expect(
      () => SyncPayloadValidator.validate(_change('tasks', payload)),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('validates Inbox marker and strict date-only due values', () {
    final invalidMarker = _taskPayload()..['inbox_content_version'] = 2;
    expect(
      () => SyncPayloadValidator.validate(_change('tasks', invalidMarker)),
      throwsA(isA<SyncValidationException>()),
    );

    final invalidDate = _taskPayload()..['due_date'] = '2026-02-30';
    expect(
      () => SyncPayloadValidator.validate(_change('tasks', invalidDate)),
      throwsA(isA<SyncValidationException>()),
    );

    final legacy = _taskPayload()..remove('due_date');
    expect(
      () => SyncPayloadValidator.validate(_change('tasks', legacy)),
      returnsNormally,
    );
    expect(legacy['due_date'], isNull);
  });

  test('validates RRULE, end date and JSON list contents', () {
    final invalidRule = _recurrencePayload()..['rrule'] = 'FREQ=NOT_A_FREQ';
    expect(
      () => SyncPayloadValidator.validate(
        _change('recurring_rules', invalidRule),
      ),
      throwsA(isA<SyncValidationException>()),
    );

    final invalidEnd = _recurrencePayload()..['end_date'] = '2025-12-31';
    expect(
      () =>
          SyncPayloadValidator.validate(_change('recurring_rules', invalidEnd)),
      throwsA(isA<SyncValidationException>()),
    );

    final invalidList = _recurrencePayload()..['exceptions_json'] = '[3]';
    expect(
      () => SyncPayloadValidator.validate(
        _change('recurring_rules', invalidList),
      ),
      throwsA(isA<SyncValidationException>()),
    );
  });

  test('accepts a canonical recurring rule payload', () {
    expect(
      () => SyncPayloadValidator.validate(
        _change('recurring_rules', _recurrencePayload()),
      ),
      returnsNormally,
    );
  });

  test('validates date identity and custom-label rules for day contexts', () {
    final canonical = _dayContextPayload();
    expect(
      () => SyncPayloadValidator.validate(_change('day_contexts', canonical)),
      returnsNormally,
    );

    final wrongIdentity = _dayContextPayload()..['date'] = '2026-01-03';
    expect(
      () =>
          SyncPayloadValidator.validate(_change('day_contexts', wrongIdentity)),
      throwsA(isA<SyncValidationException>()),
    );

    final untrimmedCustom = _dayContextPayload(
      kind: 'custom',
      customLabel: ' Family visit',
    );
    expect(
      () => SyncPayloadValidator.validate(
        _change('day_contexts', untrimmedCustom),
      ),
      throwsA(isA<SyncValidationException>()),
    );

    final presetLabel = _dayContextPayload(customLabel: 'Trip');
    expect(
      () => SyncPayloadValidator.validate(_change('day_contexts', presetLabel)),
      throwsA(isA<SyncValidationException>()),
    );
  });
}
