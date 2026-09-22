import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/timer/domain/planner_notification.dart';

import '../../helpers/runtime_auth_fakes.dart';
import '../../helpers/sqlite_setup.dart';

/// This is the mandatory Phase EF isolation suite: the same Supabase auth user
/// id in two different projects must never share ANY local Planner namespace.
void main() {
  setupSqliteForTests();

  final projectAUserX = PlannerAccountScope.provisioned(
    projectRef: projectRefA,
    authUserId: authUserIdX,
  );
  final projectBUserX = PlannerAccountScope.provisioned(
    projectRef: projectRefB,
    authUserId: authUserIdX,
  );
  final projectAUserY = PlannerAccountScope.provisioned(
    projectRef: projectRefA,
    authUserId: authUserIdY,
  );
  final legacyUserX = PlannerAccountScope.legacyStatic(authUserIdX);

  test('account scopes differ across project and user boundaries', () {
    expect(projectAUserX == projectBUserX, isFalse);
    expect(projectAUserX == projectAUserY, isFalse);
    expect(projectAUserX == legacyUserX, isFalse);
    expect(
      {
        projectAUserX.storageId,
        projectBUserX.storageId,
        projectAUserY.storageId,
        legacyUserX.storageId,
      }.length,
      4,
    );
  });

  test('database files differ across project and user boundaries', () {
    final names = <String>{
      for (final scope in [
        projectAUserX,
        projectBUserX,
        projectAUserY,
        legacyUserX,
      ])
        AppDatabase.databaseFileNameFor(accountId: scope.storageId),
    };

    expect(names.length, 4);
    expect(
      names,
      contains(
        'personal_planner_account_project_${projectRefA}__user_'
        '$authUserIdX.sqlite3',
      ),
    );
    expect(
      names,
      contains(
        'personal_planner_account_project_${projectRefB}__user_'
        '$authUserIdX.sqlite3',
      ),
    );
  });

  test('auth session and PKCE namespaces differ per project', () {
    final namespacesA = RuntimeAuthNamespaces.forProject(projectRefA);
    final namespacesB = RuntimeAuthNamespaces.forProject(projectRefB);
    const legacy = RuntimeAuthNamespaces.legacyStatic();

    expect(
      namespacesA.sessionKey,
      'personal_planner.supabase.$projectRefA.session',
    );
    expect(
      namespacesB.sessionKey,
      'personal_planner.supabase.$projectRefB.session',
    );
    expect(namespacesA.sessionKey == namespacesB.sessionKey, isFalse);
    expect(
      namespacesA.pkceKey('code-verifier') ==
          namespacesB.pkceKey('code-verifier'),
      isFalse,
    );

    // The historical global namespace cannot collide with a project namespace,
    // in either direction.
    expect(legacy.sessionKey, 'personal_planner.supabase.session');
    expect(legacy.sessionKey == namespacesA.sessionKey, isFalse);
    expect(
      legacy.pkceKey('code-verifier') == namespacesA.pkceKey('code-verifier'),
      isFalse,
    );
    expect(namespacesA.isProjectScoped, isTrue);
    expect(legacy.isProjectScoped, isFalse);
  });

  test('sync cursors are stored per canonical account scope', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db.syncDao.advanceCursor(
        projectAUserX.storageId,
        7,
        DateTime.utc(2026, 1, 1),
      );
      await db.syncDao.advanceCursor(
        projectAUserY.storageId,
        3,
        DateTime.utc(2026, 1, 1),
      );

      expect(await db.syncDao.getCursor(projectAUserX.storageId), 7);
      expect(await db.syncDao.getCursor(projectBUserX.storageId), 0);
      expect(await db.syncDao.getCursor(projectAUserY.storageId), 3);
      expect(await db.syncDao.getCursor(authUserIdX), 0);
    } finally {
      await db.close();
    }
  });

  test(
    'the sync account guard rejects another project with the same user id',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _RecordingGateway();
      try {
        final created = await CategoryRepository(db).insertCategory(
          Category(
            id: 'isolation-category',
            name: 'Private project A data',
            colorHex: '#4285F4',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // The account is project A when the push starts and becomes the same
        // auth user id in project B while the request is in flight.
        var current = projectAUserX.storageId;
        gateway.onApply = () => current = projectBUserX.storageId;
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          projectAUserX.storageId,
          currentAccountId: () => current,
        ).push();

        expect(result?.kind, SyncFailureKind.authentication);
        expect(gateway.applyCalls, 1);
        final operation = (await db.syncDao.getActiveOperationsForRecord(
          'categories',
          created.id,
        )).single;
        expect(operation.state, 'pending');
      } finally {
        await db.close();
      }
    },
  );

  test('an account mismatch that already exists before dispatch sends no mutation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = _RecordingGateway();
    try {
      final created = await CategoryRepository(db).insertCategory(
        Category(
          id: 'pre-dispatch-category',
          name: 'Private project A data',
          colorHex: '#4285F4',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      // The active account is already project B (same auth user id) before the
      // push starts, while the queued operation belongs to project A. Only the
      // canonical scope can tell those apart.
      final result = await SyncRepository.withGateway(
        db,
        gateway,
        projectAUserX.storageId,
        currentAccountId: () => projectBUserX.storageId,
      ).push();

      // Current contract: the pre-dispatch guard aborts the batch, reports a
      // failure, and nothing at all reaches the remote boundary.
      expect(result, isNotNull);
      expect(gateway.capabilityCalls, 0);
      expect(gateway.applyCalls, 0);
      expect(gateway.pullCalls, 0);
      final operation = (await db.syncDao.getActiveOperationsForRecord(
        'categories',
        created.id,
      )).single;
      expect(operation.state, 'pending');
      expect(operation.attemptCount, 0);
      expect(
        (await db.categoryDao.getCategoryById(created.id))!.serverVersion,
        isNull,
      );
    } finally {
      await db.close();
    }
  });

  test(
    'a pre-dispatch mismatch also abandons a pull before any request',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = _RecordingGateway();
      try {
        final result = await SyncRepository.withGateway(
          db,
          gateway,
          projectAUserX.storageId,
          currentAccountId: () => projectBUserX.storageId,
        ).pull();

        expect(result?.kind, SyncFailureKind.authentication);
        expect(gateway.pullCalls, 0);
        expect(gateway.applyCalls, 0);
      } finally {
        await db.close();
      }
    },
  );

  test('the notification action payload carries project-aware scope', () {
    final envelope = PlannerNotificationPayload(
      kind: PlannerNotificationKind.timer,
      taskId: 'task-1',
      sessionId: 'session-1',
      accountId: projectAUserX.storageId,
    );

    final restored = PlannerNotificationPayload.tryDecode(envelope.encode())!;

    expect(restored.accountId, projectAUserX.storageId);
    expect(restored.accountId == projectBUserX.storageId, isFalse);
  });
}

class _RecordingGateway implements SyncRemoteGateway {
  int applyCalls = 0;
  int capabilityCalls = 0;
  int pullCalls = 0;
  void Function()? onApply;

  @override
  Future<Object?> getCapabilities() async {
    capabilityCalls += 1;
    return <String, dynamic>{
      'protocol_version': 2,
      'payload_versions': <int>[1, 2],
      'schedule_duration_projection': true,
      'inbox_content_version': true,
      'due_date': true,
      'plan_title_history': true,
      'manual_actual_source': true,
      'timer_state_machine': true,
      'day_contexts': true,
      'recurrence_removal_provenance': true,
    };
  }

  @override
  Future<Object?> applyOperation({
    required String operationId,
    required String tableName,
    required String recordId,
    required String operation,
    required int? expectedServerVersion,
    required Map<String, dynamic> payload,
    required int payloadVersion,
    String? baselineToken,
  }) async {
    applyCalls += 1;
    onApply?.call();
    return <String, dynamic>{
      'status': 'applied',
      'server_version': 8,
      'change_id': 1,
      'server_timestamp': '2026-01-02T00:00:00.000Z',
    };
  }

  @override
  Future<Object?> pullChanges({
    required int afterChangeId,
    required int limit,
  }) async {
    pullCalls += 1;
    return const <Object?>[];
  }
}
