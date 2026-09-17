import 'package:flutter/foundation.dart' show immutable;

/// Sanitized outcome of one incoming provisioned Auth callback.
///
/// This deliberately carries a bounded classification and a bounded sentence,
/// never the callback URI, an authorization code, a PKCE verifier, or a token.
@immutable
class AuthCallbackNotice {
  const AuthCallbackNotice({
    required this.code,
    required this.message,
    required this.handled,
  });

  /// Safe classification, suitable for the sanitized session diagnostics.
  final String code;

  /// Bounded user-facing copy. Empty for links that are not Planner callbacks.
  final String message;

  /// True only when the callback established a session.
  final bool handled;
}

/// Copy for the outcomes a user can actually see.
///
/// A callback that cannot be completed never removes local Planner data and
/// never changes which backend is connected; it only asks for an explicit
/// retry, which is what these sentences promise.
const String authCallbackNoPendingFlowMessage =
    'That email confirmation link is not connected to a sign-in started on '
    'this device. Sign in again, or restart cloud setup for this backend.';
const String authCallbackProjectMismatchMessage =
    'That email confirmation link belongs to a different cloud backend than '
    'the one connected on this device. Reconnect that backend and open the '
    'link again.';
const String authCallbackMissingVerifierMessage =
    'That email confirmation link can no longer be completed on this device. '
    'Request a new confirmation email, or sign in with your password.';
const String authCallbackMissingCodeMessage =
    'That email confirmation link does not contain a sign-in code this device '
    'can use. Request a new confirmation email, or sign in with your password.';
const String authCallbackExchangeFailedMessage =
    'That email confirmation link could not be completed. Request a new '
    'confirmation email, or sign in with your password.';
const String authCallbackUnavailableMessage =
    'This device could not finish the email confirmation. Local Planner data '
    'is safe; try the link again, or sign in with your password.';
const String authCallbackHandledMessage =
    'Email confirmed. This device is signed in to the cloud backend.';
