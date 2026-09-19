import 'planner_uri_scheme.dart';

/// Supabase **Management** authorization callback of the provisioning Worker.
///
/// This is deliberately a different destination from the Planner user Auth
/// callback in `auth_callback.dart`:
///
/// * [AuthCallback] confirms a Planner *user account* inside the user's own
///   Supabase project (PKCE authorization code).
/// * [ManagementCallback] only says that the confidential Worker finished
///   asking Supabase for permission to create/manage the user's project.
///
/// The link carries no transaction id, provisioning capability, Management
/// access token, refresh token, or authorization code: the app already knows
/// its own durable attempt, so the only safe information the Worker needs to
/// convey is "authorization returned, resume provisioning". A link matching
/// this destination therefore can never satisfy, mutate, or complete the
/// Planner user Auth flow.
abstract final class ManagementCallback {
  /// The shared Planner custom scheme.
  static const String scheme = PlannerUriScheme.value;

  /// Host part of the callback URI (`...://management-callback`).
  static const String host = 'management-callback';

  /// The canonical Management authorization callback URI.
  static const String redirectUrl = '$scheme://$host';

  /// Matches the exact destination, optionally followed by a query/fragment.
  ///
  /// The exact prefix keeps `...://management-callback-evil` out. Any query or
  /// fragment is ignored rather than read, so nothing in an incoming link can
  /// influence what the app does beyond resuming its own durable attempt.
  static final RegExp _linkPattern = RegExp(
    '^${RegExp.escape(redirectUrl)}(?:\\?[^#]*)?(?:#.*)?\$',
  );

  /// True when [link] is exactly the Management authorization callback.
  static bool matches(String link) => _linkPattern.hasMatch(link);
}
