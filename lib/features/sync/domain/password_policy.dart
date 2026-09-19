/// Password rules Personal Planner can actually guarantee for Planner accounts.
///
/// Source of truth: this repository's own Supabase Auth configuration in
/// `supabase/config.toml` (`minimum_password_length = 6`,
/// `password_requirements = ""`). That is the only password policy Personal
/// Planner itself configures, and it matches Supabase's documented platform
/// minimum.
///
/// The provisioning Worker deliberately patches only a project's Auth redirect
/// allow-list, so a provisioned project keeps whatever password policy the
/// user's Supabase project is configured with. Supabase therefore stays the
/// final authority.
///
/// Only guaranteed rules are declared here. Complexity rules
/// (uppercase/lowercase/digit/symbol) are intentionally absent: no repository
/// evidence shows them being enforced, and showing them would tell users
/// something Personal Planner cannot promise. A password a stronger project
/// policy rejects is still caught safely by the server-side mapping in
/// `auth_repository.dart`.
abstract final class PlannerPasswordPolicy {
  /// Shortest password Supabase accepts for a Planner account.
  static const int minimumLength = 6;

  /// Every rule this build validates locally, in display order.
  static final List<PasswordRule> rules = List<PasswordRule>.unmodifiable(
    <PasswordRule>[
      PasswordRule(
        id: 'length',
        label: 'At least $minimumLength characters',
        isSatisfied: (password) => password.length >= minimumLength,
      ),
    ],
  );

  /// True when [password] satisfies every rule guaranteed locally.
  static bool isSatisfied(String password) =>
      rules.every((rule) => rule.isSatisfied(password));
}

/// One guaranteed password rule, rendered as a single live requirement line.
final class PasswordRule {
  const PasswordRule({
    required this.id,
    required this.label,
    required this.isSatisfied,
  });

  /// Stable identifier used for widget keys and tests.
  final String id;

  /// Short, user-facing description of the rule.
  final String label;

  final bool Function(String password) isSatisfied;
}
