import 'dart:async';

import '../../../core/config/auth_callback.dart';
import '../domain/auth_callback_notice.dart';
import '../domain/runtime_auth_namespaces.dart';
import '../domain/runtime_backend.dart';
import 'runtime_auth_client.dart';
import 'secure_session_storage.dart';

/// The single provisioned authorization flow this installation may complete.
///
/// A provisioned PKCE verifier is already stored per project, but the Planner
/// callback URI carries no project identity. The installation therefore allows
/// **one** pending provisioned email confirmation at a time and records which
/// project it belongs to. Starting a new flow abandons the previous one and
/// removes its verifier, and a callback is only ever exchanged when the record
/// names the runtime backend that owns the client doing the exchange.
///
/// This is what makes "callback for project A can never authenticate project B"
/// true rather than merely unlikely: B's client is only used when the record
/// names B, and A's record can never be consumed by B's client.
class ProvisionedAuthCallbackFlow {
  ProvisionedAuthCallbackFlow({
    required this.backend,
    required SecureKeyValueStore storage,
  }) : _storage = storage,
       pkceStorage = SecureSupabasePkceStorage(
         namespaces: backend.authNamespaces,
         storage: storage,
       );

  /// Installation-wide marker naming the one project with a pending flow.
  ///
  /// Not credential material: it holds a project ref, never a verifier, code,
  /// or token.
  static const String pendingFlowKey =
      'personal_planner.supabase.auth_callback.pending';

  static final RegExp _projectRefPattern = RegExp(r'^[a-z0-9]{20}$');

  final ProvisionedRuntimeBackend backend;

  /// PKCE verifier storage of [backend], namespaced by its project ref.
  final SecureSupabasePkceStorage pkceStorage;

  final SecureKeyValueStore _storage;

  String get projectRef => backend.projectRef;

  /// Project ref of the pending flow, or null when there is none.
  Future<String?> pendingProjectRef() async {
    final value = await _storage.read(key: pendingFlowKey);
    if (value == null || !_projectRefPattern.hasMatch(value)) return null;
    return value;
  }

  /// True when this project still holds a PKCE code verifier, which is what an
  /// authorization-code callback must be exchanged with.
  Future<bool> hasPendingCodeVerifier() => pkceStorage.hasPendingCodeVerifier();

  /// Records this project as the pending flow, abandoning any other one.
  ///
  /// Called before the sign-up request is sent, so the marker and the verifier
  /// the SDK writes are created together.
  Future<void> begin() async {
    final previous = await pendingProjectRef();
    if (previous != null && previous != projectRef) {
      await _discardVerifier(previous);
    }
    await _storage.write(key: pendingFlowKey, value: projectRef);
  }

  /// Forgets this project's flow: the marker when it names this project, and
  /// this project's PKCE verifier.
  ///
  /// Another project's marker is deliberately left alone, so one project's
  /// sign-out can never make a different project's pending flow unroutable.
  Future<void> clear() async {
    final pending = await _storage.read(key: pendingFlowKey);
    if (pending == projectRef) {
      await _storage.delete(key: pendingFlowKey);
    }
    await _discardVerifier(projectRef);
  }

  Future<void> _discardVerifier(String projectRef) async {
    if (!_projectRefPattern.hasMatch(projectRef)) return;
    final pkce = SecureSupabasePkceStorage(
      namespaces: RuntimeAuthNamespaces.forProject(projectRef),
      storage: _storage,
    );
    await pkce.removeItem(key: SecureSupabasePkceStorage.codeVerifierKey);
  }
}

/// Safe classification of one incoming link.
enum AuthCallbackOutcomeKind {
  /// The link is not the Planner Auth callback; nothing was touched.
  notPlannerCallback,

  /// A session was established for this project.
  handled,

  /// No provisioned sign-in is pending on this installation.
  noPendingFlow,

  /// A flow is pending, but for a different project than the active runtime.
  projectMismatch,

  /// The marker named this project, but its PKCE verifier is already gone
  /// (already exchanged, replayed, or cleared).
  missingPkceVerifier,

  /// The link carried neither an authorization code nor an Auth server error.
  missingAuthorizationCode,

  /// The Auth server rejected the confirmation (for example, an expired or
  /// already used link), so the flow is over.
  rejected,

  /// The explicit project's Auth server or transport failed the exchange.
  exchangeFailed,

  /// The callback could not be routed at all (for example, secure storage was
  /// unavailable). The pending flow is left in place for a retry.
  unavailable,
}

/// Typed, sanitized result of one callback.
class AuthCallbackOutcome {
  const AuthCallbackOutcome._(this.kind, this.notice);

  const AuthCallbackOutcome.notPlannerCallback()
    : kind = AuthCallbackOutcomeKind.notPlannerCallback,
      notice = const AuthCallbackNotice(
        code: 'auth_callback_not_planner',
        message: '',
        handled: false,
      );

  final AuthCallbackOutcomeKind kind;
  final AuthCallbackNotice notice;

  bool get handled => kind == AuthCallbackOutcomeKind.handled;

  static AuthCallbackOutcome _rejected(
    AuthCallbackOutcomeKind kind, {
    required String code,
    required String message,
  }) => AuthCallbackOutcome._(
    kind,
    AuthCallbackNotice(code: code, message: message, handled: false),
  );
}

/// Routes Planner Auth callbacks to exactly one explicit provisioned client.
///
/// One router exists per installed provisioned runtime and is created together
/// with that runtime's client. It never touches the global `Supabase.instance`
/// client, another project's PKCE namespace, or another project's session
/// storage, so the compile-time developer path keeps its own deep-link
/// behaviour through `supabase_flutter`.
class ProvisionedAuthCallbackRouter {
  ProvisionedAuthCallbackRouter({
    required this.backend,
    required this.client,
    required this.flow,
    required this.links,
    this.onOutcome,
  });

  final ProvisionedRuntimeBackend backend;

  /// Auth client of exactly this project.
  final RuntimeAuthClient client;

  /// Pending-flow bookkeeping of exactly this project.
  final ProvisionedAuthCallbackFlow flow;

  /// Observed raw link stream (the platform deep-link stream in production).
  ///
  /// Raw strings, because the registered scheme is not a valid RFC 3986 scheme
  /// and the plugin's `Uri` stream drops such links instead of reporting them.
  final Stream<String> links;

  final void Function(AuthCallbackOutcome outcome)? onOutcome;

  StreamSubscription<String>? _subscription;

  /// Starts observing links. Safe to call once; later calls are ignored.
  void start() {
    if (_subscription != null) return;
    _subscription = links.listen(
      (link) {
        if (link.isNotEmpty) unawaited(handle(link));
      },
      onError: (Object _, StackTrace _) {
        // A platform link-stream error is never a reason to disturb the local
        // Planner; the next delivered link is handled normally.
      },
    );
  }

  /// Stops observing links. Idempotent.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Routes [link] without ever throwing.
  ///
  /// [onOutcome] is notified for every Planner callback, including rejected
  /// ones, so the bounded error can be surfaced. Links that are not Planner
  /// callbacks are ignored silently.
  Future<AuthCallbackOutcome> handle(String link) async {
    final outcome = await _route(link);
    if (outcome.kind != AuthCallbackOutcomeKind.notPlannerCallback) {
      try {
        onOutcome?.call(outcome);
      } catch (_) {
        // Reporting an outcome must never break callback handling.
      }
    }
    return outcome;
  }

  Future<AuthCallbackOutcome> _route(String link) async {
    final callback = AuthCallback.tryParse(link);
    if (callback == null) {
      return const AuthCallbackOutcome.notPlannerCallback();
    }
    final String? pending;
    final bool hasVerifier;
    try {
      pending = await flow.pendingProjectRef();
      hasVerifier = pending == backend.projectRef
          ? await flow.hasPendingCodeVerifier()
          : false;
    } catch (_) {
      // Secure storage is unavailable. Never guess a project; the pending flow
      // is left in place so the link can be opened again after a retry.
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.unavailable,
        code: 'auth_callback_unavailable',
        message: authCallbackUnavailableMessage,
      );
    }
    if (pending == null) {
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.noPendingFlow,
        code: 'auth_callback_no_pending_flow',
        message: authCallbackNoPendingFlowMessage,
      );
    }
    if (pending != backend.projectRef) {
      // The link may belong to another project that is not the active runtime.
      // This client, and its PKCE namespace, are never used.
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.projectMismatch,
        code: 'auth_callback_project_mismatch',
        message: authCallbackProjectMismatchMessage,
      );
    }
    if (!hasVerifier) {
      // An already exchanged or abandoned flow. Clearing only this project's
      // stale marker keeps a replay from re-entering the exchange.
      try {
        await flow.clear();
      } catch (_) {
        // A stale marker is not worth failing the callback over.
      }
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.missingPkceVerifier,
        code: 'auth_callback_missing_verifier',
        message: authCallbackMissingVerifierMessage,
      );
    }
    if (callback.hasError) {
      // The Auth server definitively ended this flow, so its pending state is
      // cleared. Only a classification is recorded, never the description.
      try {
        await flow.clear();
      } catch (_) {
        // Clearing is best effort; the bounded error is still reported.
      }
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.rejected,
        code: 'auth_callback_rejected',
        message: authCallbackExchangeFailedMessage,
      );
    }
    final code = callback.code;
    if (code == null) {
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.missingAuthorizationCode,
        code: 'auth_callback_missing_code',
        message: authCallbackMissingCodeMessage,
      );
    }
    try {
      await client.exchangeCodeForSession(code);
      await flow.clear();
      return AuthCallbackOutcome._(
        AuthCallbackOutcomeKind.handled,
        const AuthCallbackNotice(
          code: 'auth_callback_handled',
          message: authCallbackHandledMessage,
          handled: true,
        ),
      );
    } catch (_) {
      // Never include the URI, code, or verifier in the outcome. The pending
      // flow is left intact so a network failure can be retried by opening the
      // link again.
      return AuthCallbackOutcome._rejected(
        AuthCallbackOutcomeKind.exchangeFailed,
        code: 'auth_callback_exchange_failed',
        message: authCallbackExchangeFailedMessage,
      );
    }
  }
}
