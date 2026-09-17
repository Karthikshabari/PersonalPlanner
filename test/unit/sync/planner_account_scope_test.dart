import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';

import '../../helpers/runtime_auth_fakes.dart';

void main() {
  group('PlannerAccountScope', () {
    test('provisioned scope carries projectRef and authUserId together', () {
      final scope = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );

      expect(scope.projectRef, projectRefA);
      expect(scope.authUserId, authUserIdX);
      expect(scope.isProjectScoped, isTrue);
      expect(scope.storageId, 'project_${projectRefA}__user_$authUserIdX');
      expect(PlannerAccountScope.isStorageId(scope.storageId), isTrue);
    });

    test('the same auth user id in two projects is two accounts', () {
      final a = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final b = PlannerAccountScope.provisioned(
        projectRef: projectRefB,
        authUserId: authUserIdX,
      );

      expect(a == b, isFalse);
      expect(a.storageId == b.storageId, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('two auth users in one project are two accounts', () {
      final x = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final y = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdY,
      );

      expect(x == y, isFalse);
      expect(x.storageId == y.storageId, isFalse);
    });

    test('equal inputs always produce an equal scope', () {
      final first = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final second = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.storageId, second.storageId);
    });

    test('the legacy static scope keeps the historical bare user id', () {
      final scope = PlannerAccountScope.legacyStatic(authUserIdX);

      expect(scope.projectRef, isNull);
      expect(scope.isProjectScoped, isFalse);
      expect(scope.storageId, authUserIdX);
      expect(PlannerAccountScope.isStorageId(scope.storageId), isTrue);
    });

    test('the provisioned scope is never the legacy scope', () {
      final provisioned = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final legacy = PlannerAccountScope.legacyStatic(authUserIdX);

      expect(provisioned == legacy, isFalse);
      expect(provisioned.storageId == legacy.storageId, isFalse);
    });

    test('malformed ids fail closed instead of inventing a namespace', () {
      expect(
        PlannerAccountScope.tryProvisioned(
          projectRef: 'too-short',
          authUserId: authUserIdX,
        ),
        isNull,
      );
      expect(
        PlannerAccountScope.tryProvisioned(
          projectRef: projectRefA,
          authUserId: 'account-a',
        ),
        isNull,
      );
      expect(PlannerAccountScope.tryLegacyStatic('account-a'), isNull);
      expect(
        () => PlannerAccountScope.legacyStatic('NOT-A-UUID'),
        throwsArgumentError,
      );
      expect(
        () => PlannerAccountScope.provisioned(
          projectRef: 'ABCDEFGHIJKLMNOPQRST',
          authUserId: authUserIdX,
        ),
        throwsArgumentError,
      );
    });

    test('a storage id is filesystem safe and carries no user text', () {
      final scope = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );

      for (final forbidden in ['/', '\\', '.', ' ', '@', ':', '..']) {
        expect(scope.storageId.contains(forbidden), isFalse);
      }
      expect(
        PlannerAccountScope.isProjectScopedStorageId(scope.storageId),
        isTrue,
      );
      expect(
        PlannerAccountScope.isProjectScopedStorageId(authUserIdX),
        isFalse,
      );
    });
  });

  group('AppDatabase account file names', () {
    test('the anonymous database keeps its historical name', () {
      expect(
        AppDatabase.databaseFileNameFor(),
        AppDatabase.anonymousDatabaseFileName,
      );
      expect(AppDatabase.anonymousDatabaseFileName, 'personal_planner.sqlite3');
    });

    test('the same user id in two projects resolves to two databases', () {
      final a = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final b = PlannerAccountScope.provisioned(
        projectRef: projectRefB,
        authUserId: authUserIdX,
      );

      expect(
        AppDatabase.databaseFileNameFor(accountId: a.storageId),
        'personal_planner_account_project_${projectRefA}__user_'
        '$authUserIdX.sqlite3',
      );
      expect(
        AppDatabase.databaseFileNameFor(accountId: a.storageId) ==
            AppDatabase.databaseFileNameFor(accountId: b.storageId),
        isFalse,
      );
    });

    test('two users in one project resolve to two databases', () {
      final x = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdX,
      );
      final y = PlannerAccountScope.provisioned(
        projectRef: projectRefA,
        authUserId: authUserIdY,
      );

      expect(
        AppDatabase.databaseFileNameFor(accountId: x.storageId) ==
            AppDatabase.databaseFileNameFor(accountId: y.storageId),
        isFalse,
      );
    });

    test('the legacy static account keeps its historical file name', () {
      expect(
        AppDatabase.databaseFileNameFor(
          accountId: PlannerAccountScope.legacyStatic(authUserIdX).storageId,
        ),
        'personal_planner_account_$authUserIdX.sqlite3',
      );
    });

    test('any other account id shape is rejected before it can be a path', () {
      for (final invalid in [
        '../../personal_planner',
        'project_x__user_y',
        'project_${projectRefA}__user_account-a',
        'Project_${projectRefA}__user_$authUserIdX/',
      ]) {
        expect(
          () => AppDatabase.databaseFileNameFor(accountId: invalid),
          throwsArgumentError,
          reason: 'expected $invalid to be rejected',
        );
      }
    });
  });
}
