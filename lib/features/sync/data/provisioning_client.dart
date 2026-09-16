import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/config/provisioning_config.dart';
import '../domain/provisioning_state.dart';

/// Why a provisioning request failed.
enum ProvisioningErrorKind {
  /// The control plane could not be reached.
  network,

  /// The control plane did not answer in time.
  timeout,

  /// The control plane answered with a sanitized error code.
  worker,

  /// The control plane answered in a way this client cannot trust.
  protocol,
}

/// How a failed provisioning request should be treated.
enum ProvisioningFailureClass {
  retryable,
  actionRequired,
  terminal,
  restartRequired,
  protocol,
}

/// Single typed failure for every unsuccessful provisioning request.
///
/// The message never contains a capability, a header value, or a raw upstream
/// body: only the sanitized Worker error code and the HTTP status.
class ProvisioningApiException implements Exception {
  const ProvisioningApiException(
    this.kind,
    this.message, {
    this.code,
    this.statusCode,
  });

  final ProvisioningErrorKind kind;
  final String message;
  final String? code;
  final int? statusCode;

  ProvisioningFailureClass get failureClass => switch (kind) {
    ProvisioningErrorKind.network ||
    ProvisioningErrorKind.timeout => ProvisioningFailureClass.retryable,
    ProvisioningErrorKind.protocol => ProvisioningFailureClass.protocol,
    ProvisioningErrorKind.worker => classifyProvisioningErrorCode(
      code,
      statusCode,
    ),
  };

  @override
  String toString() => message;
}

/// Maps the production Worker's sanitized error codes onto Flutter treatment.
///
/// Transient transport problems never become terminal, and an unknown code is
/// treated as a protocol problem rather than guessed.
ProvisioningFailureClass classifyProvisioningErrorCode(
  String? code,
  int? statusCode,
) => switch (code) {
  'oauth_expired' ||
  'oauth_state_invalid' ||
  'provisioning_expired' => ProvisioningFailureClass.restartRequired,
  'organization_not_found' => ProvisioningFailureClass.actionRequired,
  'organization_discovery_failed' ||
  'project_creation_failed' ||
  'migration_failed' ||
  'verification_indeterminate' ||
  'runtime_config_unavailable' ||
  'operation_in_progress' ||
  'rate_limited' => ProvisioningFailureClass.retryable,
  'project_identity_ambiguous' ||
  'migration_history_mismatch' ||
  'verification_failed' => ProvisioningFailureClass.terminal,
  'invalid_request' => ProvisioningFailureClass.protocol,
  _ =>
    statusCode == 429 || (statusCode ?? 0) >= 500
        ? ProvisioningFailureClass.retryable
        : statusCode == 410
        ? ProvisioningFailureClass.restartRequired
        : ProvisioningFailureClass.protocol,
};

/// Minimal request/response boundary so tests never need a real network.
abstract interface class ProvisioningTransport {
  Future<ProvisioningHttpResponse> send(ProvisioningHttpRequest request);
}

class ProvisioningHttpRequest {
  const ProvisioningHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;

  @override
  String toString() => '$method $uri';
}

class ProvisioningHttpResponse {
  const ProvisioningHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Default transport: bounded, non-redirecting, and strictly read-only.
///
/// `dart:io` is used deliberately instead of adding an HTTP package; the
/// Planner targets Linux desktop and Android, both of which provide it.
class IoProvisioningTransport implements ProvisioningTransport {
  IoProvisioningTransport({
    HttpClient? client,
    this.timeout = const Duration(seconds: 25),
    this.maxResponseBytes = 64 * 1024,
  }) : _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final HttpClient _client;
  final Duration timeout;
  final int maxResponseBytes;

  @override
  Future<ProvisioningHttpResponse> send(ProvisioningHttpRequest request) async {
    try {
      final httpRequest = await _client
          .openUrl(request.method, request.uri)
          .timeout(timeout);
      httpRequest.followRedirects = false;
      request.headers.forEach(httpRequest.headers.set);
      final body = request.body;
      if (body != null) httpRequest.write(body);

      final response = await httpRequest.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxResponseBytes) {
          throw const ProvisioningApiException(
            ProvisioningErrorKind.protocol,
            'The provisioning response exceeded the accepted size.',
          );
        }
      }
      return ProvisioningHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes.takeBytes()),
      );
    } on ProvisioningApiException {
      rethrow;
    } on TimeoutException {
      throw const ProvisioningApiException(
        ProvisioningErrorKind.timeout,
        'The provisioning request timed out.',
      );
    } on SocketException {
      throw const ProvisioningApiException(
        ProvisioningErrorKind.network,
        'The provisioning service could not be reached.',
      );
    } on HttpException {
      throw const ProvisioningApiException(
        ProvisioningErrorKind.network,
        'The provisioning request failed.',
      );
    } on FormatException {
      throw const ProvisioningApiException(
        ProvisioningErrorKind.protocol,
        'The provisioning response was not valid UTF-8 text.',
      );
    }
  }
}

/// Client-facing result of `POST /v1/provisioning/transactions`.
///
/// [capability] is the provisioning capability: a short-lived credential for
/// this one transaction. It is never a Supabase session token and never a
/// Management token, and it must be moved into secure storage immediately.
class ProvisioningGrant {
  const ProvisioningGrant({
    required this.transactionId,
    required this.capability,
    required this.authorizationUrl,
    required this.expiresIn,
  });

  final String transactionId;
  final String capability;
  final Uri authorizationUrl;
  final Duration expiresIn;

  /// Intentionally omits [capability].
  @override
  String toString() =>
      'ProvisioningGrant(transactionId: $transactionId, '
      'expiresIn: ${expiresIn.inSeconds}s)';
}

/// One selectable user-owned Supabase organization.
class ProvisioningOrganization {
  const ProvisioningOrganization({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is ProvisioningOrganization &&
      other.id == id &&
      other.name == name &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(id, name, slug);

  @override
  String toString() => 'ProvisioningOrganization($slug)';
}

/// The client-safe runtime configuration returned once provisioning is ready.
class ProvisioningRuntimeConfig {
  const ProvisioningRuntimeConfig({
    required this.projectRef,
    required this.projectUrl,
    required this.publishableKey,
  });

  final String projectRef;
  final String projectUrl;
  final String publishableKey;

  /// Intentionally omits [publishableKey]: it is client-safe, but it has no
  /// business being echoed into diagnostics.
  @override
  String toString() =>
      'ProvisioningRuntimeConfig(projectRef: $projectRef, '
      'projectUrl: $projectUrl)';
}

/// The subset of the transaction snapshot Flutter actually needs.
class ProvisioningSnapshot {
  const ProvisioningSnapshot({
    required this.transactionId,
    required this.state,
    this.projectRef,
    this.organizationSlug,
    this.requestedProjectName,
    this.errorCode,
    this.expiresAt,
    this.runtimeConfig,
  });

  final String transactionId;
  final ProvisioningState state;
  final String? projectRef;
  final String? organizationSlug;
  final String? requestedProjectName;
  final String? errorCode;
  final DateTime? expiresAt;
  final ProvisioningRuntimeConfig? runtimeConfig;

  bool get isReady => state == ProvisioningState.ready;

  @override
  String toString() =>
      'ProvisioningSnapshot(transactionId: $transactionId, '
      'state: ${state.wireName})';
}

/// Thin, strongly typed client for the frozen production provisioning API.
///
/// It only constructs requests and parses responses; orchestration, state
/// transitions, and persistence belong to `ProvisioningCoordinator`.
class ProvisioningClient {
  ProvisioningClient({required Uri baseUrl, required this.transport})
    : _base = _normalizeBase(baseUrl);

  /// Builds a client from build-time configuration.
  factory ProvisioningClient.fromConfig({ProvisioningTransport? transport}) {
    final base = ProvisioningConfig.baseUri;
    if (base == null) {
      throw StateError('The provisioning control-plane URL is not configured.');
    }
    return ProvisioningClient(
      baseUrl: base,
      transport: transport ?? IoProvisioningTransport(),
    );
  }

  static const maxOrganizations = 100;

  static final RegExp _transactionIdPattern = RegExp(r'^[a-f0-9]{32}$');
  static final RegExp _capabilityPattern = RegExp(r'^[A-Za-z0-9_-]{32,256}$');
  static final RegExp _projectRefPattern = RegExp(r'^[a-z]{20}$');

  final Uri _base;
  final ProvisioningTransport transport;

  Future<ProvisioningGrant> createTransaction() async {
    final json = _decodeObject(
      await _send(
        method: 'POST',
        path: '/v1/provisioning/transactions',
        body: const <String, dynamic>{},
      ),
    );
    final transactionId = _requireString(json, 'transactionId');
    if (!_transactionIdPattern.hasMatch(transactionId)) {
      throw _protocol(
        'The provisioning service returned an invalid transaction id.',
      );
    }
    final capability = _requireString(json, 'accessToken');
    if (!_capabilityPattern.hasMatch(capability)) {
      throw _protocol(
        'The provisioning service returned an invalid capability.',
      );
    }
    final authorizationUrl = Uri.tryParse(
      _requireString(json, 'authorizationUrl'),
    );
    if (authorizationUrl == null ||
        authorizationUrl.scheme != 'https' ||
        authorizationUrl.host.isEmpty) {
      throw _protocol(
        'The provisioning service returned an invalid authorization URL.',
      );
    }
    final expiresIn = json['expiresIn'];
    if (expiresIn is! num ||
        expiresIn <= 0 ||
        expiresIn != expiresIn.roundToDouble() ||
        expiresIn > 24 * 60 * 60) {
      throw _protocol('The provisioning service returned an invalid expiry.');
    }
    return ProvisioningGrant(
      transactionId: transactionId,
      capability: capability,
      authorizationUrl: authorizationUrl,
      expiresIn: Duration(seconds: expiresIn.toInt()),
    );
  }

  Future<ProvisioningSnapshot> snapshot(
    String transactionId, {
    required String capability,
  }) async {
    _requireTransactionId(transactionId);
    return _parseSnapshot(
      transactionId,
      await _send(
        method: 'GET',
        path: _transactionPath(transactionId),
        capability: capability,
      ),
    );
  }

  Future<List<ProvisioningOrganization>> organizations(
    String transactionId, {
    required String capability,
  }) async {
    _requireTransactionId(transactionId);
    final json = _decodeObject(
      await _send(
        method: 'GET',
        path: '${_transactionPath(transactionId)}/organizations',
        capability: capability,
      ),
    );
    final raw = json['organizations'];
    if (raw is! List || raw.length > maxOrganizations) {
      throw _protocol(
        'The provisioning service returned an unusable organization list.',
      );
    }
    final organizations = <ProvisioningOrganization>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        throw _protocol(
          'The provisioning service returned an unusable organization entry.',
        );
      }
      organizations.add(
        ProvisioningOrganization(
          id: _requireString(entry, 'id'),
          name: _requireString(entry, 'name'),
          slug: _requireString(entry, 'slug'),
        ),
      );
    }
    return List<ProvisioningOrganization>.unmodifiable(organizations);
  }

  Future<ProvisioningSnapshot> selectOrganization(
    String transactionId, {
    required String capability,
    required String slug,
    required String projectName,
    required String idempotencyKey,
  }) async {
    _requireTransactionId(transactionId);
    return _parseSnapshot(
      transactionId,
      await _send(
        method: 'POST',
        path: '${_transactionPath(transactionId)}/organization',
        capability: capability,
        body: <String, dynamic>{
          'slug': slug,
          'projectName': projectName,
          'idempotencyKey': idempotencyKey,
        },
      ),
    );
  }

  Future<ProvisioningSnapshot> create(
    String transactionId, {
    required String capability,
  }) => _post(transactionId, capability: capability, operation: 'create');

  Future<ProvisioningSnapshot> reconcile(
    String transactionId, {
    required String capability,
  }) => _post(transactionId, capability: capability, operation: 'reconcile');

  Future<ProvisioningSnapshot> migrate(
    String transactionId, {
    required String capability,
  }) => _post(transactionId, capability: capability, operation: 'migrate');

  Future<ProvisioningSnapshot> verify(
    String transactionId, {
    required String capability,
  }) => _post(transactionId, capability: capability, operation: 'verify');

  Future<ProvisioningSnapshot> _post(
    String transactionId, {
    required String capability,
    required String operation,
  }) async {
    _requireTransactionId(transactionId);
    return _parseSnapshot(
      transactionId,
      await _send(
        method: 'POST',
        path: '${_transactionPath(transactionId)}/$operation',
        capability: capability,
        body: const <String, dynamic>{},
      ),
    );
  }

  Future<ProvisioningHttpResponse> _send({
    required String method,
    required String path,
    String? capability,
    Map<String, dynamic>? body,
  }) {
    final headers = <String, String>{'accept': 'application/json'};
    if (capability != null) {
      headers['authorization'] = 'Provisioning $capability';
    }
    if (body != null) headers['content-type'] = 'application/json';
    return transport.send(
      ProvisioningHttpRequest(
        method: method,
        uri: Uri.parse('${_base.toString()}$path'),
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Map<String, dynamic> _decodeObject(ProvisioningHttpResponse response) {
    if (!response.isSuccess) throw _workerError(response);
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw _protocol('The provisioning service returned a non-JSON response.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw _protocol(
        'The provisioning service returned an unexpected response shape.',
      );
    }
    return decoded;
  }

  ProvisioningSnapshot _parseSnapshot(
    String transactionId,
    ProvisioningHttpResponse response,
  ) {
    final json = _decodeObject(response);
    final stateName = _requireString(json, 'state');
    final state = ProvisioningState.tryFromWireName(stateName);
    if (state == null || !state.isWorkerReported) {
      throw _protocol(
        'The provisioning service reported an unsupported state.',
      );
    }
    final projectRef = _optionalString(json, 'projectRef');
    if (projectRef != null && !_projectRefPattern.hasMatch(projectRef)) {
      throw _protocol(
        'The provisioning service reported an invalid project ref.',
      );
    }
    final rawConfig = json['runtimeConfig'];
    ProvisioningRuntimeConfig? runtimeConfig;
    if (rawConfig != null) {
      if (rawConfig is! Map<String, dynamic>) {
        throw _protocol(
          'The provisioning service returned an unusable runtime configuration.',
        );
      }
      runtimeConfig = ProvisioningRuntimeConfig(
        projectRef: _requireString(rawConfig, 'projectRef'),
        projectUrl: _requireString(rawConfig, 'projectUrl'),
        publishableKey: _requireString(rawConfig, 'publishableKey'),
      );
    }
    // The frozen contract exposes the configuration only once the backend is
    // verified; anything else is a contract violation, not something to guess.
    if (state == ProvisioningState.ready && runtimeConfig == null) {
      throw _protocol(
        'The provisioning service reported ready without a runtime configuration.',
      );
    }
    if (state != ProvisioningState.ready && runtimeConfig != null) {
      throw _protocol(
        'The provisioning service returned a runtime configuration before ready.',
      );
    }
    final expiresAt = json['expiresAt'];
    if (expiresAt != null && (expiresAt is! int || expiresAt <= 0)) {
      throw _protocol('The provisioning service reported an invalid expiry.');
    }
    return ProvisioningSnapshot(
      transactionId: transactionId,
      state: state,
      projectRef: projectRef,
      organizationSlug: _optionalString(json, 'organizationSlug'),
      requestedProjectName: _optionalString(json, 'requestedProjectName'),
      errorCode: _optionalString(json, 'error'),
      expiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      runtimeConfig: runtimeConfig,
    );
  }

  ProvisioningApiException _workerError(ProvisioningHttpResponse response) {
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['error'];
        if (raw is String && raw.isNotEmpty && raw.length <= 64) code = raw;
      }
    } on FormatException {
      code = null;
    }
    if (code == null) {
      return _protocol(
        'The provisioning service returned an unusable error response '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return ProvisioningApiException(
      ProvisioningErrorKind.worker,
      'Provisioning stopped: $code (HTTP ${response.statusCode}).',
      code: code,
      statusCode: response.statusCode,
    );
  }

  void _requireTransactionId(String transactionId) {
    if (!_transactionIdPattern.hasMatch(transactionId)) {
      throw _protocol(
        'A provisioning transaction id must be 32 lowercase hex characters.',
      );
    }
  }

  static String _transactionPath(String transactionId) =>
      '/v1/provisioning/transactions/$transactionId';

  static Uri _normalizeBase(Uri baseUrl) {
    if (baseUrl.scheme != 'https' || baseUrl.host.isEmpty) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'must be an https URL with a host',
      );
    }
    return baseUrl.replace(path: baseUrl.path.replaceAll(RegExp(r'/+$'), ''));
  }

  static ProvisioningApiException _protocol(
    String message, {
    int? statusCode,
  }) => ProvisioningApiException(
    ProvisioningErrorKind.protocol,
    message,
    statusCode: statusCode,
  );
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ProvisioningApiException(
      ProvisioningErrorKind.protocol,
      'The provisioning response is missing $key.',
    );
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw ProvisioningApiException(
      ProvisioningErrorKind.protocol,
      'The provisioning response has an unusable $key.',
    );
  }
  return value;
}
