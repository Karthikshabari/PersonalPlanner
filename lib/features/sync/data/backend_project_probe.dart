import 'dart:async';
import 'dart:io';

/// What a bounded probe of the user's Supabase project host learned.
enum BackendProjectProbeResult {
  /// The project host answered for this project.
  exists,

  /// The Auth health route answered 404; exact project existence is unknown.
  missing,

  /// Auth rejected the health request; project existence is unknown.
  accessDenied,

  /// Anything else — DNS, TLS, timeout, outage, rate limit — proves nothing.
  indeterminate,
}

/// Asks the user's Supabase project host whether it still serves this project.
///
/// Deliberately narrow:
///
/// * an HTTP 404 is recorded separately, but is not proof of deletion;
/// * every transport problem (including DNS failure, which a deleted project
///   also causes, and which a broken network causes too) is [indeterminate];
/// * a 5xx/429 is [indeterminate].
///
/// Local-first behaviour never depends on this probe: it runs while the cloud
/// UI is visible and only reports host reachability. Exact deletion requires
/// a Management project lookup after user authorization.
class BackendProjectProbe {
  BackendProjectProbe({
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 6));

  final HttpClient _client;
  final Duration timeout;

  /// Probes `<projectUrl>/auth/v1/health` with the saved publishable API key.
  /// Supabase's gateway requires this key even for the health endpoint.
  Future<BackendProjectProbeResult> probe(
    Uri projectUrl, {
    required String publishableKey,
  }) async {
    if (projectUrl.scheme != 'https' || projectUrl.host.isEmpty) {
      return BackendProjectProbeResult.indeterminate;
    }
    try {
      final request = await _client
          .getUrl(projectUrl.replace(path: '/auth/v1/health'))
          .timeout(timeout);
      request.headers.set('apikey', publishableKey);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode == 404) {
        return BackendProjectProbeResult.missing;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return BackendProjectProbeResult.accessDenied;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return BackendProjectProbeResult.exists;
      }
      // 429 and 5xx prove nothing about deletion.
      return BackendProjectProbeResult.indeterminate;
    } on TimeoutException {
      return BackendProjectProbeResult.indeterminate;
    } on SocketException {
      // A deleted project removes its DNS record, but so does an outage, a
      // captive portal, or an offline device. Never evidence of deletion.
      return BackendProjectProbeResult.indeterminate;
    } on HandshakeException {
      return BackendProjectProbeResult.indeterminate;
    } on HttpException {
      return BackendProjectProbeResult.indeterminate;
    }
  }

  void close() => _client.close(force: true);
}
