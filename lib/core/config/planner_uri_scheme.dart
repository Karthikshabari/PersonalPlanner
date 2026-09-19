/// The custom URI scheme owned by Personal Planner.
///
/// One definition for the whole application: every Planner callback kind
/// (Planner user Auth confirmation and Supabase Management authorization)
/// shares this scheme, the Android manifest registers it, the Linux desktop
/// entry registers it as an `x-scheme-handler`, and the provisioning Worker's
/// browser hand-off pages deep-link with it.
///
/// RFC 3986-valid: schemes may contain letters, digits, `+`, `-`, and `.`, but
/// not `_`. An earlier value contained an underscore, which made the callback
/// unusable because Supabase Auth rejected the redirect and the browser could
/// not resolve the scheme at all.
abstract final class PlannerUriScheme {
  /// This is the deep-link scheme only. The Android applicationId/package and
  /// the Linux GApplication id are separate identifiers and are unchanged.
  static const String value = 'com.personalplanner.personalplanner';
}
