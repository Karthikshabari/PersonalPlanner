import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/domain/password_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The repository only guarantees what Personal Planner itself configures
/// (`supabase/config.toml`: `minimum_password_length = 6`,
/// `password_requirements = ""`). Anything stronger belongs to the user's own
/// Supabase project and is reported from the server answer instead of guessed.
void main() {
  group('PlannerPasswordPolicy', () {
    test('declares exactly the guaranteed minimum length rule', () {
      expect(PlannerPasswordPolicy.minimumLength, 6);
      expect(PlannerPasswordPolicy.rules, hasLength(1));
      expect(PlannerPasswordPolicy.rules.single.id, 'length');
      expect(PlannerPasswordPolicy.rules.single.label, 'At least 6 characters');
    });

    test('accepts anything at or above the guaranteed minimum', () {
      expect(PlannerPasswordPolicy.isSatisfied('abcdef'), isTrue);
      expect(PlannerPasswordPolicy.isSatisfied('admin 123'), isTrue);
      expect(PlannerPasswordPolicy.isSatisfied('abcde'), isFalse);
      expect(PlannerPasswordPolicy.isSatisfied(''), isFalse);
    });
  });

  group('server-side password rejection mapping', () {
    test('recognises every shape Supabase reports a weak password with', () {
      expect(
        isPasswordPolicyFailure(
          AuthWeakPasswordException(
            message: 'Password should contain at least one character of each',
            statusCode: '422',
            reasons: const <String>['characters'],
          ),
        ),
        isTrue,
      );
      expect(
        isPasswordPolicyFailure(
          const AuthException(
            'Password is known to be weak and easy to guess',
            code: 'weak_password',
          ),
        ),
        isTrue,
      );
      // Legacy servers omit the code and only send the message.
      expect(
        isPasswordPolicyFailure(
          const AuthException('Password should be at least 6 characters'),
        ),
        isTrue,
      );
      expect(
        isPasswordPolicyFailure(
          const AuthException('Invalid login credentials'),
        ),
        isFalse,
      );
    });

    test('never reports a rejected password as a network problem', () {
      final message = safeAuthError(
        const AuthException(
          'Password is known to be weak and easy to guess',
          code: 'weak_password',
        ),
      );
      expect(message, passwordPolicyErrorMessage());
      expect(message, contains('at least 6 characters'));
      expect(message, isNot(contains('Network')));
    });

    test('keeps real transport failures as transport failures', () {
      expect(
        safeAuthError(Exception('SocketException: connection refused')),
        'Network unavailable. Your local data is still safe.',
      );
    });
  });
}
