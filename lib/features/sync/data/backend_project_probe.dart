import 'dart:async';
import 'dart:io';

/// What a bounded probe of the user's Supabase project host learned.
enum BackendProjectProbeResult {
  /// The project host answered for this project.
  exists,

  /// Supabase answered 404 for the project host: the project is gone.
  missing,

  /// Anything else — DNS, TLS, timeout, outage, rate limit — proves nothing.
  indeterminate,
}

/// Asks the user's Supabase project host whether it still serves this project.
///
/// Deliberately narrow:
///
/// * an HTTP 404 is the only authoritative "missing" answer;
/// * every transport problem (including DNS failure, which a deleted project
///   also causes, and which a broken network causes too) is [indeterminate];
/// * a 5xx/429 is [indeterminate].
///
/// Local-first behaviour never depends on this probe: it runs while the cloud
/// UI is visible, and its only effect is to surface an authoritative deletion.
class BackendProjectProbe {
  BackendProjectProbe({
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 6));

  final HttpClient _client;
  final Duration timeout;

  /// Probes `<projectUrl>/auth/v1/health` for [projectUrl].
  Future<BackendProjectProbeResult> probe(Uri projectUrl) async {
    if (projectUrl.scheme != 'https' || projectUrl.host.isEmpty) {
      return BackendProjectProbeResult.indeterminate;
    }
    try {
      final request = await _client
          .getUrl(projectUrl.replace(path: '/auth/v1/health'))
          .timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode == 404) {
        return BackendProjectProbeResult.missing;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return BackendProjectProbeResult.exists;
      }
      // 401/403/429 and 5xx all prove nothing about deletion.
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
