import 'planner_uri_scheme.dart';

enum ManagementCallbackResult { completed, cancelled, failed, invalid, unknown }

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
/// access token, refresh token, or authorization code. Its optional `result`
/// describes the browser outcome for UI recovery; the Worker still decides
/// whether a grant exists. It cannot complete the Planner user Auth flow.
abstract final class ManagementCallback {
  /// The shared Planner custom scheme.
  static const String scheme = PlannerUriScheme.value;

  /// Host part of the callback URI (`...://management-callback`).
  static const String host = 'management-callback';

  /// The canonical Management authorization callback URI.
  static const String redirectUrl = '$scheme://$host';

  /// Matches the exact destination, optionally followed by a query/fragment.
  ///
  /// The exact prefix keeps `...://management-callback-evil` out. Only the
  /// bounded `result` query value is interpreted by [resultOf].
  static final RegExp _linkPattern = RegExp(
    '^${RegExp.escape(redirectUrl)}(?:\\?[^#]*)?(?:#.*)?\$',
  );

  /// True when [link] is exactly the Management authorization callback.
  static bool matches(String link) => _linkPattern.hasMatch(link);

  /// A browser outcome is only a UI hint. The Worker remains authoritative
  /// about whether it holds a Management grant for the pending transaction.
  static ManagementCallbackResult resultOf(String link) {
    if (!matches(link)) return ManagementCallbackResult.invalid;
    final result = Uri.tryParse(link)?.queryParameters['result'];
    return switch (result) {
      'completed' => ManagementCallbackResult.completed,
      'cancelled' => ManagementCallbackResult.cancelled,
      'failed' => ManagementCallbackResult.failed,
      'invalid' => ManagementCallbackResult.invalid,
      _ => ManagementCallbackResult.unknown,
    };
  }
}
