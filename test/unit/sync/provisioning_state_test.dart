import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

/// The Worker's `STATES` array in `provisioning_poc/src/production.ts`.
const _workerStateNames = <String>[
  'authorization_pending',
  'organization_selected',
  'project_creating',
  'project_reconciliation_required',
  'project_retry_authorized',
  'project_waiting',
  'migrating',
  'migration_reconciliation_required',
  'verifying',
  'ready',
  'terminal_error',
  'expired',
];

/// The Worker's `NEXT` table, transcribed from
/// `provisioning_poc/src/production.ts`.
const _workerNext = <ProvisioningState, Set<ProvisioningState>>{
  ProvisioningState.authorizationPending: {
    ProvisioningState.organizationSelected,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.organizationSelected: {
    ProvisioningState.projectCreating,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.projectCreating: {
    ProvisioningState.projectReconciliationRequired,
    ProvisioningState.projectWaiting,
    ProvisioningState.expired,
  },
  ProvisioningState.projectReconciliationRequired: {
    ProvisioningState.projectRetryAuthorized,
    ProvisioningState.projectWaiting,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.projectRetryAuthorized: {
    ProvisioningState.projectCreating,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.projectWaiting: {
    ProvisioningState.migrating,
    ProvisioningState.expired,
  },
  ProvisioningState.migrating: {
    ProvisioningState.migrationReconciliationRequired,
    ProvisioningState.verifying,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.migrationReconciliationRequired: {
    ProvisioningState.migrating,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.verifying: {
    ProvisioningState.ready,
    ProvisioningState.terminalError,
    ProvisioningState.expired,
  },
  ProvisioningState.ready: {ProvisioningState.expired},
  ProvisioningState.terminalError: {ProvisioningState.expired},
  ProvisioningState.expired: <ProvisioningState>{},
};

void main() {
  test('wire names match the Worker state names exactly', () {
    final workerStates = ProvisioningState.values
        .where((state) => state.isWorkerReported)
        .map((state) => state.wireName)
        .toList();

    expect(workerStates, equals(_workerStateNames));
    expect(ProvisioningState.localOnly.wireName, equals('local_only'));
    expect(
      ProvisioningState.tryFromWireName('local_only'),
      equals(ProvisioningState.localOnly),
    );
  });

  test('wire names parse back to their states', () {
    for (final state in ProvisioningState.values) {
      expect(
        ProvisioningState.tryFromWireName(state.wireName),
        equals(state),
        reason: state.wireName,
      );
    }
    expect(ProvisioningState.tryFromWireName('not_a_state'), isNull);
    expect(ProvisioningState.tryFromWireName(''), isNull);
    expect(ProvisioningState.tryFromWireName('READY'), isNull);
  });

  test('allowed next states mirror the Worker transition table', () {
    for (final state in ProvisioningState.values) {
      final expected = state == ProvisioningState.localOnly
          ? const {ProvisioningState.authorizationPending}
          : _workerNext[state]!;
      expect(state.allowedNextStates, equals(expected), reason: state.wireName);
    }
  });

  test(
    'only the Worker transitions plus the local bootstrap edge are legal',
    () {
      for (final from in ProvisioningState.values) {
        for (final to in ProvisioningState.values) {
          final expected = from == to
              ? true
              : from == ProvisioningState.localOnly
              ? to == ProvisioningState.authorizationPending
              : _workerNext[from]!.contains(to);
          expect(
            canTransition(from, to),
            expected,
            reason: '${from.wireName} -> ${to.wireName}',
          );
        }
      }
    },
  );

  test('reconciliation and retry states keep the transaction resumable', () {
    expect(
      ProvisioningState.authorizationPending.canTransitionTo(
        ProvisioningState.organizationSelected,
      ),
      isTrue,
    );
    expect(
      ProvisioningState.projectCreating.canTransitionTo(
        ProvisioningState.projectReconciliationRequired,
      ),
      isTrue,
    );
    expect(
      ProvisioningState.projectReconciliationRequired.canTransitionTo(
        ProvisioningState.projectRetryAuthorized,
      ),
      isTrue,
    );
    expect(
      ProvisioningState.projectRetryAuthorized.canTransitionTo(
        ProvisioningState.projectCreating,
      ),
      isTrue,
    );
    expect(
      ProvisioningState.migrating.canTransitionTo(
        ProvisioningState.migrationReconciliationRequired,
      ),
      isTrue,
    );
    expect(
      ProvisioningState.migrationReconciliationRequired.canTransitionTo(
        ProvisioningState.migrating,
      ),
      isTrue,
    );
  });

  test(
    'ready, terminal and expired states cannot be skipped or re-entered',
    () {
      expect(
        ProvisioningState.verifying.canTransitionTo(ProvisioningState.ready),
        isTrue,
      );
      expect(
        ProvisioningState.authorizationPending.canTransitionTo(
          ProvisioningState.ready,
        ),
        isFalse,
      );
      expect(
        ProvisioningState.ready.canTransitionTo(ProvisioningState.verifying),
        isFalse,
      );
      expect(
        ProvisioningState.ready.canTransitionTo(
          ProvisioningState.terminalError,
        ),
        isFalse,
      );
      expect(
        ProvisioningState.terminalError.canTransitionTo(
          ProvisioningState.authorizationPending,
        ),
        isFalse,
      );
      expect(
        ProvisioningState.expired.canTransitionTo(
          ProvisioningState.authorizationPending,
        ),
        isFalse,
      );
      expect(ProvisioningState.expired.allowedNextStates, isEmpty);
    },
  );

  test(
    'state classification separates local, progress, ready and terminal',
    () {
      expect(ProvisioningState.localOnly.isWorkerReported, isFalse);
      expect(ProvisioningState.localOnly.isInProgress, isFalse);
      expect(ProvisioningState.localOnly.isTerminal, isFalse);
      expect(ProvisioningState.localOnly.isReady, isFalse);

      for (final state in ProvisioningState.values.where(
        (candidate) => candidate.isWorkerReported,
      )) {
        final expectedTerminal =
            state == ProvisioningState.terminalError ||
            state == ProvisioningState.expired;
        expect(state.isTerminal, expectedTerminal, reason: state.wireName);
        expect(state.isReady, state == ProvisioningState.ready);
        expect(
          state.isInProgress,
          !expectedTerminal && state != ProvisioningState.ready,
          reason: state.wireName,
        );
      }
    },
  );

  test('illegal transition exception names both states', () {
    const error = ProvisioningStateTransitionException(
      from: ProvisioningState.authorizationPending,
      to: ProvisioningState.ready,
    );

    expect(error.toString(), contains('authorization_pending'));
    expect(error.toString(), contains('ready'));
  });
}
