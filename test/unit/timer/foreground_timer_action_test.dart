import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/timer/platform/android_foreground_timer.dart';

void main() {
  late _FakePendingActionStore store;

  setUp(() {
    store = _FakePendingActionStore();
    AndroidForegroundTimer.pendingActionStore = store;
    AndroidForegroundTimer.pendingAction.value = null;
  });

  tearDown(() {
    AndroidForegroundTimer.pendingActionStore = null;
    AndroidForegroundTimer.pendingAction.value = null;
  });

  test('foreground action preserves the exact persisted timer identity', () {
    final at = DateTime.utc(2026, 2, 1, 9, 10, 11);
    final action = PendingForegroundTimerAction(
      actionId: 'action-1',
      action: AndroidForegroundTimer.pauseButtonId,
      taskId: 'task-1',
      sessionId: '11111111-1111-4111-8111-111111111111',
      accountId: 'account-1',
      ownerDeviceId: '22222222-2222-4222-8222-222222222222',
      expectedRunningSince: at,
      expectedDurationSec: 90,
      expectedStateRevision: 7,
      occurredAt: at.add(const Duration(seconds: 3)),
    );

    final decoded = PendingForegroundTimerAction.fromJsonString(
      jsonEncode(action.toJson()),
    );
    expect(decoded?.actionId, action.actionId);
    expect(decoded?.sessionId, action.sessionId);
    expect(decoded?.accountId, action.accountId);
    expect(decoded?.ownerDeviceId, action.ownerDeviceId);
    expect(decoded?.expectedRunningSince, action.expectedRunningSince);
    expect(decoded?.expectedDurationSec, action.expectedDurationSec);
    expect(decoded?.expectedStateRevision, action.expectedStateRevision);
    expect(decoded?.occurredAt, action.occurredAt);
  });

  test(
    'malformed foreground envelopes are ignored without a database action',
    () {
      expect(PendingForegroundTimerAction.fromJsonString('not-json'), isNull);
      expect(
        PendingForegroundTimerAction.fromJson(const {
          'action_id': 'missing-time',
          'action': AndroidForegroundTimer.stopButtonId,
        }),
        isNull,
      );
    },
  );

  test(
    'failed action dispatch retains its injected durable envelope for retry',
    () async {
      final at = DateTime.utc(2026, 2, 1, 9, 10, 11);
      final action = PendingForegroundTimerAction(
        actionId: 'retry-action',
        action: AndroidForegroundTimer.stopButtonId,
        taskId: 'task-1',
        sessionId: '11111111-1111-4111-8111-111111111111',
        accountId: 'account-1',
        ownerDeviceId: '22222222-2222-4222-8222-222222222222',
        expectedRunningSince: at,
        expectedDurationSec: 90,
        expectedStateRevision: 7,
        occurredAt: at,
      );

      await AndroidForegroundTimer.persistPendingAction(action);
      expect(
        (await AndroidForegroundTimer.takePendingAction())?.actionId,
        'retry-action',
      );

      // A failed dispatcher does not call acknowledge. The original envelope
      // and original timestamp remain available to a restart retry.
      expect(
        (await AndroidForegroundTimer.takePendingAction())?.occurredAt,
        at,
      );
      await AndroidForegroundTimer().acknowledgePendingAction('other-action');
      expect(store.raw, isNotNull);

      await AndroidForegroundTimer().acknowledgePendingAction(action.actionId);
      expect(store.raw, isNull);
      expect(await AndroidForegroundTimer.takePendingAction(), isNull);
    },
  );
}

class _FakePendingActionStore implements PendingForegroundTimerActionStore {
  String? raw;

  @override
  Future<void> remove() async {
    raw = null;
  }

  @override
  Future<String?> read() async => raw;

  @override
  Future<void> write(String value) async {
    raw = value;
  }
}
