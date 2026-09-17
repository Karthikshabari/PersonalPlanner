import 'package:flutter/foundation.dart' show immutable;

/// Canonical Planner Auth callback destination.
///
/// One definition for the whole application: provisioned email sign-up sends
/// it as `emailRedirectTo`, the provisioned deep-link handler accepts only it,
/// and the canonical provisioning Worker adds it to a new project's Supabase
/// Auth redirect allow list.
///
/// The Android manifest registers the same scheme and host. The URI is
/// deliberately free of query parameters and of a trailing slash: Supabase
/// appends the authorization code as a query parameter, so the exact value is
/// also the value stored in a project's redirect allow list.
abstract final class AuthCallback {
  /// Custom URL scheme owned by the Planner.
  ///
  /// Note: this scheme contains an underscore, which RFC 3986 does not allow in
  /// a scheme. It is preserved because Android already registers it. Dart's
  /// `Uri` parser rejects such a scheme and the platform deep-link plugin's
  /// `Uri` stream silently drops the callback, so the provisioned handler
  /// consumes the raw delivered link through [tryParse] instead.
  static const String scheme = 'com.personalplanner.personal_planner';

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
