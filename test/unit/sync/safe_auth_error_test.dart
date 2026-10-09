import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('safeAuthError', () {
    test('keeps wrong details as wrong details', () {
      expect(
        safeAuthError(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        'Email or password is incorrect.',
      );
    });

    test('keeps an unconfirmed email as unconfirmed', () {
      expect(
        safeAuthError(
          const AuthApiException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
        ),
        'This email has not been confirmed yet. Open the confirmation link '
        'from your email, then log in again.',
      );
    });

    test('keeps an existing account as existing', () {
      expect(
        safeAuthError(
          const AuthApiException(
            'User already registered',
            statusCode: '422',
            code: 'user_already_exists',
          ),
        ),
        'That email is already registered.',
      );
    });

    test('keeps a lost connection as a network problem', () {
      expect(
        safeAuthError(
          AuthRetryableFetchException(
            message: 'ClientException with SocketException: Connection refused',
          ),
        ),
        'Network unavailable. Your local data is still safe.',
      );
    });

    test('explains too many attempts', () {
      expect(
        safeAuthError(
          const AuthApiException(
            'For security purposes, you can only request this after 30 seconds.',
            statusCode: '429',
            code: 'over_request_rate_limit',
          ),
        ),
        plannerAuthRateLimitedMessage,
      );
      expect(
        safeAuthError(
          const AuthApiException(
            'Email rate limit exceeded',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
        ),
        plannerAuthRateLimitedMessage,
      );
    });

    test('explains a project that does not accept new accounts', () {
      expect(
        safeAuthError(
          const AuthApiException(
            'Signups not allowed for this instance',
            statusCode: '422',
            code: 'signup_disabled',
          ),
        ),
        plannerAuthSignupDisabledMessage,
      );
    });

    test('explains a project that rejected the app', () {
      expect(
        safeAuthError(
          const AuthApiException('Invalid API key', statusCode: '401'),
        ),
        plannerAuthProjectRejectedMessage,
      );
      expect(
        safeAuthError(const AuthApiException('Forbidden', statusCode: '403')),
        plannerAuthProjectRejectedMessage,
      );
    });

    test('explains a project that is not answering', () {
      expect(
        safeAuthError(
          AuthRetryableFetchException(
            message: 'upstream error',
            statusCode: '503',
          ),
        ),
        plannerAuthServerUnavailableMessage,
      );
    });

    test('explains a lost connection without a recognisable message', () {
      expect(
        safeAuthError(
          AuthRetryableFetchException(message: 'Failed host lookup'),
        ),
        plannerAuthNetworkMessage,
      );
    });

    test('never shows the raw server text', () {
      final errors = <Object>[
        const AuthApiException(
          'For security purposes, you can only request this after 30 seconds.',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
        const AuthApiException(
          'Signups not allowed for this instance',
          statusCode: '422',
          code: 'signup_disabled',
        ),
        const AuthApiException('Invalid API key', statusCode: '401'),
        const AuthApiException('Forbidden', statusCode: '403'),
        AuthRetryableFetchException(
          message: 'upstream error',
          statusCode: '503',
        ),
        AuthRetryableFetchException(message: 'Failed host lookup'),
      ];
      for (final error in errors) {
        final message = safeAuthError(error);
        expect(message, isNot(matches(RegExp(r'\b(401|403|429|503)\b'))));
        expect(message, isNot(contains('Exception')));
      }
    });
  });
}
