import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The single place the app hands an address to the operating system.
///
/// Every platform takes the same path: `launchUrl(..., externalApplication)`
/// with no `canLaunchUrl` gate (it reports false for valid https links on some
/// Windows/macOS configurations) and no per-platform process fallback.

/// Longest part of an address shown in the failure message; Copy keeps it all.
const int _shownUrlLength = 120;

/// Repeat taps on the same address inside this window open one browser window.
const Duration _repeatWindow = Duration(milliseconds: 1500);

final Map<String, Stopwatch> _recentLaunches = <String, Stopwatch>{};

/// Clears the repeat-tap memory so tests do not influence each other.
@visibleForTesting
void resetExternalLinkGuard() => _recentLaunches.clear();

/// True for an absolute https address with a host.
bool isHttpsUri(Uri uri) => uri.scheme == 'https' && uri.host.isNotEmpty;

/// True for https addresses on supabase.com or one of its subdomains.
bool isSupabaseUri(Uri uri) =>
    isHttpsUri(uri) &&
    (uri.host == 'supabase.com' || uri.host.endsWith('.supabase.com'));

/// Opens [uri] in the user's browser and reports whether the platform accepted
/// it. Never throws.
///
/// Only https is allowed. [allowed] narrows that further (for example to
/// Supabase hosts); a rejected address is not launched.
Future<bool> launchExternalUri(
  Uri uri, {
  bool Function(Uri uri)? allowed,
}) async {
  if (!isHttpsUri(uri) || !(allowed?.call(uri) ?? true)) return false;
  final key = uri.toString();
  final recent = _recentLaunches[key];
  if (recent != null && recent.elapsed < _repeatWindow) return true;
  _recentLaunches[key] = Stopwatch()..start();
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _recentLaunches.remove(key);
    return opened;
  } catch (_) {
    _recentLaunches.remove(key);
    return false;
  }
}

/// Opens [uri] and, when that is not possible, tells the user how to get there
/// by hand: a SnackBar with the address and a Copy action.
Future<void> openExternalLink(
  BuildContext context,
  Uri uri, {
  bool Function(Uri uri)? allowed,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final opened = await launchExternalUri(uri, allowed: allowed);
  if (opened || !context.mounted) return;
  showExternalLinkFallback(context, uri, messenger: messenger);
}

/// Shows the "browser could not be opened" SnackBar for [uri].
void showExternalLinkFallback(
  BuildContext context,
  Uri uri, {
  ScaffoldMessengerState? messenger,
}) {
  final target = messenger ?? ScaffoldMessenger.maybeOf(context);
  if (target == null) return;
  final text = uri.toString();
  final shown = text.length <= _shownUrlLength
      ? text
      : '${text.substring(0, _shownUrlLength)}…';
  target
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('external-link-fallback'),
        content: Text(
          'The browser could not be opened. Open this address yourself:\n'
          '$shown',
        ),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
      ),
    );
}
