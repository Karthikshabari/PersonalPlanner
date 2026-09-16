/// Build-time configuration for the Personal Planner provisioning control plane.
///
/// This is deliberately separate from the Supabase runtime configuration: the
/// provisioning base URL points at the Cloudflare Worker that performs
/// provisioning/repair, while the Supabase values describe a user-owned
/// project. A missing provisioning URL never affects the local Planner; it only
/// leaves the provisioning subsystem unavailable.
abstract final class ProvisioningConfig {
  static const baseUrl = String.fromEnvironment('PROVISIONING_BASE_URL');

  /// The control-plane base URI, or null when it is missing or unusable.
  ///
  /// Only https, a host, and an optional path prefix are accepted; query
  /// strings, fragments, and user info are rejected so request paths can be
  /// appended directly and predictably.
  static Uri? get baseUri {
    final raw = baseUrl.trim();
    if (raw.isEmpty || raw.contains('PASTE_')) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      return null;
    }
    final path = parsed.path.replaceAll(RegExp(r'/+$'), '');
    return parsed.replace(path: path);
  }

  static bool get isConfigured => baseUri != null;
}
