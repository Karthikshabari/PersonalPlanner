import 'package:flutter/foundation.dart' show immutable;

import 'planner_uri_scheme.dart';

/// Canonical Planner Auth callback destination.
///
/// One definition for the whole application: provisioned email sign-up sends
/// either it or the Worker's HTTPS confirmation landing page as
/// `emailRedirectTo`, the provisioned deep-link handler accepts only it, and
/// the canonical provisioning Worker adds both to a new project's Supabase Auth
/// redirect allow list.
///
/// The Android manifest registers the same scheme and host. The URI is
/// deliberately free of query parameters and of a trailing slash: Supabase
/// appends the authorization code as a query parameter, so the exact value is
/// also the value stored in a project's redirect allow list.
abstract final class AuthCallback {
  /// The shared Planner custom URL scheme.
  static const String scheme = PlannerUriScheme.value;

  /// Host part of the callback URI (`...://login-callback`).
  static const String host = 'login-callback';

  /// The canonical Planner Auth callback URI.
  static const String redirectUrl = '$scheme://$host';

  /// Matches the exact callback destination, then its query, then its fragment.
  ///
  /// The exact prefix keeps `...://login-callback-evil` or another host out.
  static final RegExp _linkPattern = RegExp(
    '^${RegExp.escape(redirectUrl)}(?:\\?([^#]*))?(?:#(.*))?\$',
  );

  /// Parses a raw delivered link, or returns null when it is not a Planner
  /// callback.
  ///
  /// Raw-string routing is kept deliberately: the platform delivers the link
  /// as a string, and matching the exact destination here keeps rejection of
  /// wrong hosts, wrong paths, and malformed links explicit. The scheme is now
  /// RFC-valid, so URI-based consumers (for example `supabase_flutter`'s own
  /// observer on the legacy static path) receive the same callback.
  ///
  /// Only the authorization code and the Auth server's own error fields are
  /// read. Implicit-flow tokens in the link are ignored on purpose: the
  /// provisioned path accepts the PKCE authorization-code flow only.
  static AuthCallbackLink? tryParse(String link) {
    final match = _linkPattern.firstMatch(link);
    if (match == null) return null;
    final query = match.group(1) ?? '';
    final fragment = match.group(2) ?? '';
    final combined = query.isEmpty
        ? fragment
        : fragment.isEmpty
        ? query
        : '$query&$fragment';
    final Map<String, String> parameters;
    try {
      parameters = combined.isEmpty
          ? const <String, String>{}
          : Uri.splitQueryString(combined);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return AuthCallbackLink(
      code: _nonEmpty(parameters['code']),
      error:
          _nonEmpty(parameters['error']) ?? _nonEmpty(parameters['error_code']),
      errorDescription: _nonEmpty(parameters['error_description']),
    );
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}

/// Parsed, sanitized contents of one Planner Auth callback link.
@immutable
class AuthCallbackLink {
  const AuthCallbackLink({this.code, this.error, this.errorDescription});

  /// PKCE authorization code, when the callback carries one.
  final String? code;

  /// Auth server error code, when the flow was rejected.
  final String? error;

  /// Auth server error description, when one was provided.
  final String? errorDescription;

  bool get hasError => error != null || errorDescription != null;
}
