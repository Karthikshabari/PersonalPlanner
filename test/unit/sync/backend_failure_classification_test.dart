import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/sync_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:personal_planner/features/sync/domain/sync_models.dart';
import 'package:personal_planner/features/sync/domain/sync_validation.dart';

/// Phase H backend-failure taxonomy.
///
/// The distinction that matters: a transient transport failure, an invalid
/// session, an un-migrated backend and a backend that no longer exists must not
/// collapse into one user-facing state, and none of them may be treated as
/// permission to change stored configuration or delete anything.
void main() {
  test('a missing project host is a backend failure, not a retry', () {
    final failure = classifySyncFailure(
      Exception(
        "ClientException with SocketException: Failed host lookup: "
        "'abcdefghijklmnopqrst.supabase.co' "
        '(OS Error: Name or service not known, errno = -2)',
      ),
    );

    expect(failure.kind, SyncFailureKind.backendUnavailable);
    expect(failure.message, cloudBackendUnreachableMessage);
  });

  test('an explicit project-not-found answer is a backend failure', () {
    final failure = classifySyncFailure(
      Exception(
        'PostgrestException(message: Not Found, code: 404, hint: '
        'https://abcdefghijklmnopqrst.supabase.co/rest/v1)',
      ),
    );

    expect(failure.kind, SyncFailureKind.backendUnavailable);
  });

  test('transient transport failures stay retryable and change nothing', () {
    for (final error in <Object>[
      Exception('SocketException: Connection reset by peer'),
      Exception('SocketException: Connection timed out'),
      Exception('ClientException: connection closed before full header'),
      Exception('PostgrestException(message: server error, code: 503)'),
    ]) {
      final failure = classifySyncFailure(error);

      expect(
        failure.kind,
        SyncFailureKind.retryable,
        reason: '$error must stay a retryable transport failure',
      );
      expect(failure.message, isNot(cloudBackendUnreachableMessage));
    }
  });

  test('an invalid session is authentication, never a missing backend', () {
    for (final error in <Object>[
      Exception('PostgrestException(message: JWT expired, code: PGRST301)'),
      Exception('AuthApiException(message: invalid claim, statusCode: 401)'),
      Exception('403 Forbidden'),
    ]) {
      expect(
        classifySyncFailure(error).kind,
        SyncFailureKind.authentication,
        reason: '$error',
      );
    }
  });

  test('baseline fencing keeps its recoverable protocol meaning', () {
    final failure = classifySyncFailure(
      Exception('this device does not own the initial baseline claim'),
    );

    expect(failure.kind, SyncFailureKind.retryable);
    expect(isInitialBaselineFencingFailure(failure), isTrue);
  });

  test('invalid payloads stay invalid data', () {
    expect(
      classifySyncFailure(const SyncValidationException('bad payload')).kind,
      SyncFailureKind.invalidData,
    );
    expect(
      classifySyncFailure(const FormatException('bad json')).kind,
      SyncFailureKind.invalidData,
    );
  });

  test('bare "not found" is not enough to call a backend missing', () {
    // A missing RPC on an otherwise reachable project is an un-migrated
    // backend, which is a different, explicit state.
    final failure = classifySyncFailure(
      Exception('could not find the function planner_sync_account_state'),
    );
    expect(failure.kind, isNot(SyncFailureKind.backendUnavailable));

    expect(looksLikeUnavailableBackend('relation does not exist'), isFalse);
    expect(looksLikeUnavailableBackend('404 not found'), isFalse);
  });

  test('the backend-unavailable copy never promises deletion or data loss', () {
    final message = cloudBackendUnreachableMessage.toLowerCase();

    expect(message, contains('local planner data'));
    expect(message, contains('safe'));
    expect(message, isNot(contains('delete')));
    expect(message, isNot(contains('removed')));
  });

  test('a backend outage keeps queued work retryable, not permanent', () {
    final unavailable = classifySyncFailure(
      Exception("SocketException: Failed host lookup: 'x.supabase.co'"),
    );
    final transient = classifySyncFailure(
      Exception('SocketException: Connection timed out'),
    );
    final invalid = classifySyncFailure(
      const SyncValidationException('bad payload'),
    );

    expect(unavailable.keepsOperationQueued, isTrue);
    expect(transient.keepsOperationQueued, isTrue);
    expect(invalid.keepsOperationQueued, isFalse);
  });

  group('SQLSTATE classification (DB-005)', () {
    test('deterministic 22023 rejection is permanent', () {
      final failure = classifySyncFailure(
        const PostgrestException(
          message: 'Finished timer sessions cannot be reopened',
          code: '22023',
          details: 'Bad Request',
        ),
      );

      expect(failure.kind, SyncFailureKind.permanent);
      expect(
        failure.message,
        contains('Finished timer sessions cannot be reopened'),
      );
    });

    test('serialization failure is retryable', () {
      final failure = classifySyncFailure(
        const PostgrestException(
          message: 'could not serialize access',
          code: '40001',
        ),
      );

      expect(failure.kind, SyncFailureKind.retryable);
    });

    test('missing JWT is authentication', () {
      final failure = classifySyncFailure(
        const PostgrestException(
          message: 'Authentication required',
          code: '42501',
        ),
      );

      expect(failure.kind, SyncFailureKind.authentication);
    });

    test('fencing rejection keeps its retryable fencing message', () {
      final failure = classifySyncFailure(
        const PostgrestException(
          message:
              'No active initial baseline claim: this account is being '
              'established by a fenced first synchronization',
          code: 'P0001',
        ),
      );

      expect(isInitialBaselineFencingFailure(failure), isTrue);
    });
  });
}
