/// Build-time public Supabase configuration.
///
/// Do not replace these defaults with real credentials in source control. The
/// URL and publishable key are supplied with `--dart-define` (or a local
/// `--dart-define-from-file` JSON file). A missing or invalid configuration
/// intentionally leaves the planner in offline-only mode.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured {
    final parsed = Uri.tryParse(url);
    return publishableKey.trim().isNotEmpty &&
        parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty &&
        !url.contains('PASTE_');
  }
}
