import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/auth_callback.dart';
import 'package:personal_planner/features/sync/data/auth_repository.dart';
import 'package:personal_planner/features/sync/data/runtime_auth_callback.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/domain/auth_callback_notice.dart';
import 'package:personal_planner/features/sync/domain/auth_session_controller.dart';
import 'package:personal_planner/features/sync/domain/runtime_auth_namespaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/runtime_auth_fakes.dart';

/// Pre-E2E Auth callback handling for provisioned backends.
///
/// The invariants under test:
/// * the callback URI is one canonical value, used for sign-up and matching;
/// * a callback is exchanged only by the explicit Auth client of the project
///   that started the flow, with that project's PKCE namespace;
/// * a callback for project A can never authenticate project B, the
///   compile-time developer backend, or a global singleton client;
/// * replayed, unmatched, unrelated, and failed callbacks are bounded errors
///   that change no session.
void main() {
  String plannerCallback({String code = 'authorization-code'}) =>
      '${AuthCallback.redirectUrl}?code=$code';

  ProvisionedAuthCallbackFlow flowFor(
    FakeSecureKeyValueStore store, {
    String projectRef = projectRefA,
    String publishableKey = publishableKeyA,
  }) => ProvisionedAuthCallbackFlow(
    backend: testProvisionedBackend(
      projectRef: projectRef,
      publishableKey: publishableKey,
    ),
    storage: store,
  );

  /// Records the verifier GoTrue stores when a PKCE flow starts.
  Future<void> seedVerifier(ProvisionedAuthCallbackFlow flow) =>
      flow.pkceStorage.setItem(
        key: SecureSupabasePkceStorage.codeVerifierKey,
        value: 'code-verifier-secret',
      );

  group('canonical callback', () {
    test('is pinned to one value', () {
      expect(
        AuthCallback.redirectUrl,
        'com.personalplanner.personalplanner://login-callback',
      );
      expect(AuthCallback.scheme, 'com.personalplanner.personalplanner');
      expect(AuthCallback.host, 'login-callback');
    });

    test('parses only the Planner callback destination', () {
      // The canonical URI must be RFC 3986-valid. The previous scheme contained
      // an underscore, so Supabase Auth fell back to the Site URL and Dart's
      // Uri parser rejected the delivered link.
      final canonical = Uri.tryParse(AuthCallback.redirectUrl);
      expect(canonical, isNotNull);
      expect(canonical!.scheme, AuthCallback.scheme);
      expect(canonical.host, AuthCallback.host);
      expect(canonical.path.isEmpty, isTrue);
      expect(canonical.query.isEmpty, isTrue);
      expect(canonical.fragment.isEmpty, isTrue);

      expect(AuthCallback.tryParse(plannerCallback()), isNotNull);
      expect(AuthCallback.tryParse(AuthCallback.redirectUrl), isNotNull);
      expect(
        AuthCallback.tryParse('${AuthCallback.redirectUrl}/extra-path'),
        isNull,
      );
      expect(
        AuthCallback.tryParse(
          'com.personalplanner.personalplanner://other-host',
        ),
        isNull,
      );
      expect(
        AuthCallback.tryParse(
          'com.personalplanner.personalplanner://login-callback-other',
        ),
        isNull,
      );
      expect(AuthCallback.tryParse('https://login-callback'), isNull);
      expect(
        AuthCallback.tryParse('${AuthCallback.redirectUrl}-evil?code=x'),
        isNull,
      );
      expect(
        AuthCallback.tryParse('${AuthCallback.redirectUrl}?code=abc%20123')
            ?.code,
        'abc 123',
      );
      expect(
        AuthCallback.tryParse(
          '${AuthCallback.redirectUrl}?error=access_denied'
          '&error_description=Link%20expired',
        )?.hasError,
        isTrue,
      );
    });
  });

  group('pending provisioned flow bookkeeping', () {
    test('records one project and preserves its own PKCE namespace', () async {
      final store = FakeSecureKeyValueStore();
      final flowA = flowFor(store);

      await flowA.begin();
      await seedVerifier(flowA);

      expect(await flowA.pendingProjectRef(), projectRefA);
      expect(await flowA.hasPendingCodeVerifier(), isTrue);
      expect(
        store.values.keys,
        contains(
          RuntimeAuthNamespaces.forProject(projectRefA)
              .pkceKey(SecureSupabasePkceStorage.codeVerifierKey),
        ),
      );
    });

    test('starting another project abandons the previous flow only', () async {
      final store = FakeSecureKeyValueStore();
      final flowA = flowFor(store);
      final flowB = flowFor(
        store,
        projectRef: projectRefB,
        publishableKey: publishableKeyB,
      );

      await flowA.begin();
      await seedVerifier(flowA);
      await flowB.begin();
      await seedVerifier(flowB);

      expect(await flowB.pendingProjectRef(), projectRefB);
      // Project A's pending flow was abandoned when B's began, so at most one
      // provisioned authorization flow is ever pending.
      expect(await flowA.hasPendingCodeVerifier(), isFalse);
      expect(await flowB.hasPendingCodeVerifier(), isTrue);
    });

    test(
      "clearing one project's flow never removes another project's marker",
      () async {
        final store = FakeSecureKeyValueStore();
        final flowA = flowFor(store);
        final flowB = flowFor(
          store,
          projectRef: projectRefB,
          publishableKey: publishableKeyB,
        );

        await flowB.begin();
        await seedVerifier(flowB);
        await flowA.clear();

        expect(await flowB.pendingProjectRef(), projectRefB);
        expect(await flowB.hasPendingCodeVerifier(), isTrue);
      },
    );

    test(
      'sign-out abandons the pending flow of exactly this project',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        final repository = AuthRepository(client, provisionedAuthFlow: flow);
        addTearDown(client.close);

        await flow.begin();
        await seedVerifier(flow);
        await repository.signOut();

        expect(await flow.pendingProjectRef(), isNull);
        expect(await flow.hasPendingCodeVerifier(), isFalse);
      },
    );

    test(
      'provisioned sign-up records the flow and uses the canonical redirect',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        final repository = AuthRepository(client, provisionedAuthFlow: flow);
        addTearDown(client.close);

        await repository.signUp(' Person@Example.com ', 'password');

        expect(client.signUpCalls, hasLength(1));
        expect(client.signUpCalls.single.email, 'Person@Example.com');
        expect(
          client.signUpCalls.single.emailRedirectTo,
          AuthCallback.redirectUrl,
        );
        expect(await flow.pendingProjectRef(), projectRefA);
      },
    );
  });

  group('PKCE key contract with the installed SDK', () {
    test(
      'the verifier key the router checks is the key GoTrue writes',
      () async {
        final store = FakeSecureKeyValueStore();
        final backend = testProvisionedBackend();
        final storage = SecureSupabasePkceStorage(
          namespaces: backend.authNamespaces,
          storage: store,
        );
        final auth = GoTrueClient(
          url: backend.projectUrl,
          asyncStorage: storage,
          autoRefreshToken: false,
        );

        expect(await storage.hasPendingCodeVerifier(), isFalse);

        // Building an OAuth URL locally is what makes GoTrue generate and store
        // the PKCE code verifier; no network call happens here.
        await auth.getOAuthSignInUrl(
          provider: OAuthProvider.github,
          redirectTo: AuthCallback.redirectUrl,
        );

        expect(await storage.hasPendingCodeVerifier(), isTrue);
        expect(
          store.values.keys,
          contains(
            RuntimeAuthNamespaces.forProject(projectRefA)
                .pkceKey(SecureSupabasePkceStorage.codeVerifierKey),
          ),
        );
        expect(
          store.values.keys,
          isNot(contains(SecureSupabasePkceStorage.codeVerifierKey)),
          reason: 'the verifier must never use a project-independent key',
        );
      },
    );
  });

  group('provisioned callback routing', () {
    test(
      'project A pending callback is handled only by the A client',
      () async {
        final store = FakeSecureKeyValueStore();
        final flowA = flowFor(store);
        final clientA = FakeRuntimeAuthClient();
        final clientB = FakeRuntimeAuthClient();
        addTearDown(clientA.close);
        addTearDown(clientB.close);
        final session = testAuthSession(authUserId: authUserIdX);
        clientA.callbackSession = session;
        final outcomes = <AuthCallbackOutcome>[];

        await flowA.begin();
        await seedVerifier(flowA);

        final router = ProvisionedAuthCallbackRouter(
          backend: testProvisionedBackend(),
          client: clientA,
          flow: flowA,
          links: const Stream<String>.empty(),
          onOutcome: outcomes.add,
        );
        addTearDown(router.dispose);

        final outcome = await router.handle(plannerCallback());

        expect(outcome.kind, AuthCallbackOutcomeKind.handled);
        expect(outcome.notice.handled, isTrue);
        expect(clientA.acceptedCallbackCodes, ['authorization-code']);
        expect(clientA.session, session);
        expect(clientB.acceptedCallbackCodes, isEmpty);
        expect(clientB.session, isNull);
        expect(outcomes.single.notice.code, 'auth_callback_handled');
        // Nothing about the handled callback remains pending.
        expect(await flowA.pendingProjectRef(), isNull);
      },
    );

    test(
      'project A callback cannot authenticate an active project B',
      () async {
        final store = FakeSecureKeyValueStore();
        final flowA = flowFor(store);
        final flowB = flowFor(
          store,
          projectRef: projectRefB,
          publishableKey: publishableKeyB,
        );
        final clientB = FakeRuntimeAuthClient();
        addTearDown(clientB.close);
        clientB.callbackSession = testAuthSession(authUserId: authUserIdY);

        await flowA.begin();
        await seedVerifier(flowA);

        final routerB = ProvisionedAuthCallbackRouter(
          backend: flowB.backend,
          client: clientB,
          flow: flowB,
          links: const Stream<String>.empty(),
        );
        addTearDown(routerB.dispose);

        final outcome = await routerB.handle(plannerCallback());

        expect(outcome.kind, AuthCallbackOutcomeKind.projectMismatch);
        expect(outcome.notice.message, authCallbackProjectMismatchMessage);
        // Zero B session mutation, zero B Auth call, and neither project's
        // pending state was consumed.
        expect(clientB.acceptedCallbackCodes, isEmpty);
        expect(clientB.session, isNull);
        // The installation marker still names A, and B has no verifier of its
        // own, so B could never exchange this callback even if it tried.
        expect(await flowB.pendingProjectRef(), projectRefA);
        expect(await flowB.hasPendingCodeVerifier(), isFalse);
        expect(await flowA.pendingProjectRef(), projectRefA);
        expect(await flowA.hasPendingCodeVerifier(), isTrue);
      },
    );

    test(
      'a disconnected project never reconnects through an old callback',
      () async {
        final store = FakeSecureKeyValueStore();
        final flowA = flowFor(store);
        final backendB = testProvisionedBackend(
          projectRef: projectRefB,
          publishableKey: publishableKeyB,
        );
        final flowB = ProvisionedAuthCallbackFlow(
          backend: backendB,
          storage: store,
        );
        final clientB = FakeRuntimeAuthClient();
        addTearDown(clientB.close);

        // A's sign-out already abandoned A's flow when it was disconnected.
        await flowA.begin();
        await seedVerifier(flowA);
        await flowA.clear();

        final routerB = ProvisionedAuthCallbackRouter(
          backend: backendB,
          client: clientB,
          flow: flowB,
          links: const Stream<String>.empty(),
        );
        addTearDown(routerB.dispose);

        final outcome = await routerB.handle(plannerCallback());

        expect(outcome.kind, AuthCallbackOutcomeKind.noPendingFlow);
        expect(clientB.acceptedCallbackCodes, isEmpty);
        expect(clientB.session, isNull);
        expect(await flowA.hasPendingCodeVerifier(), isFalse);
        expect(await flowA.pendingProjectRef(), isNull);
      },
    );

    test(
      'a Planner callback with no pending flow is a bounded error',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        addTearDown(client.close);
        final outcomes = <AuthCallbackOutcome>[];

        final router = ProvisionedAuthCallbackRouter(
          backend: flow.backend,
          client: client,
          flow: flow,
          links: const Stream<String>.empty(),
          onOutcome: outcomes.add,
        );
        addTearDown(router.dispose);

        final outcome = await router.handle(plannerCallback());

        expect(outcome.kind, AuthCallbackOutcomeKind.noPendingFlow);
        expect(outcome.notice.handled, isFalse);
        expect(outcome.notice.message, authCallbackNoPendingFlowMessage);
        expect(outcomes.single.notice.code, 'auth_callback_no_pending_flow');
        expect(client.acceptedCallbackCodes, isEmpty);
        expect(client.session, isNull);
      },
    );

    test('a replayed callback is rejected without a second exchange', () async {
      final store = FakeSecureKeyValueStore();
      final flow = flowFor(store);
      final client = FakeRuntimeAuthClient();
      addTearDown(client.close);
      client.callbackSession = testAuthSession(authUserId: authUserIdX);
      final router = ProvisionedAuthCallbackRouter(
        backend: flow.backend,
        client: client,
        flow: flow,
        links: const Stream<String>.empty(),
      );
      addTearDown(router.dispose);

      await flow.begin();
      await seedVerifier(flow);

      expect(
        (await router.handle(plannerCallback())).kind,
        AuthCallbackOutcomeKind.handled,
      );
      // GoTrue consumes the verifier on the first successful exchange; the
      // application must not exchange the same code again.
      final replay = await router.handle(plannerCallback());

      expect(replay.kind, AuthCallbackOutcomeKind.noPendingFlow);
      expect(client.acceptedCallbackCodes, hasLength(1));
      expect(client.session?.user.id, authUserIdX);
    });

    test('a rejected exchange leaves the session untouched and reports a bounded failure', () async {
      final store = FakeSecureKeyValueStore();
      final flow = flowFor(store);
      final client = FakeRuntimeAuthClient()
        ..callbackError = const AuthException('Invalid flow state');
      addTearDown(client.close);
      final outcomes = <AuthCallbackOutcome>[];
      final router = ProvisionedAuthCallbackRouter(
        backend: flow.backend,
        client: client,
        flow: flow,
        links: const Stream<String>.empty(),
        onOutcome: outcomes.add,
      );
      addTearDown(router.dispose);

      await flow.begin();
      await seedVerifier(flow);

      final outcome = await router.handle(plannerCallback());

      expect(outcome.kind, AuthCallbackOutcomeKind.exchangeFailed);
      expect(outcome.notice.message, authCallbackExchangeFailedMessage);
      expect(client.session, isNull);
      // The pending flow survives so the user can retry after a transient
      // failure; no other project's state is involved at all.
      expect(await flow.pendingProjectRef(), projectRefA);
      expect(await flow.hasPendingCodeVerifier(), isTrue);
      expect(outcomes.single.notice.handled, isFalse);
    });

    test('an unrelated deep link is ignored without touching Auth', () async {
      final store = FakeSecureKeyValueStore();
      final flow = flowFor(store);
      final client = FakeRuntimeAuthClient();
      addTearDown(client.close);
      final outcomes = <AuthCallbackOutcome>[];
      final router = ProvisionedAuthCallbackRouter(
        backend: flow.backend,
        client: client,
        flow: flow,
        links: const Stream<String>.empty(),
        onOutcome: outcomes.add,
      );
      addTearDown(router.dispose);

      final outcome = await router.handle(
        'https://example.test/not-the-planner',
      );

      expect(outcome.kind, AuthCallbackOutcomeKind.notPlannerCallback);
      expect(client.acceptedCallbackCodes, isEmpty);
      expect(outcomes, isEmpty);
    });

    test(
      'an Auth-server rejection ends the flow with a bounded error',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        addTearDown(client.close);
        final router = ProvisionedAuthCallbackRouter(
          backend: flow.backend,
          client: client,
          flow: flow,
          links: const Stream<String>.empty(),
        );
        addTearDown(router.dispose);

        await flow.begin();
        await seedVerifier(flow);
        final outcome = await router.handle(
          '${AuthCallback.redirectUrl}?error=access_denied'
          '&error_description=Email+link+expired',
        );

        expect(outcome.kind, AuthCallbackOutcomeKind.rejected);
        expect(outcome.notice.message, authCallbackExchangeFailedMessage);
        expect(outcome.notice.message, isNot(contains('Email link expired')));
        expect(client.acceptedCallbackCodes, isEmpty);
        // The server definitively ended the flow, so its pending state is gone.
        expect(await flow.pendingProjectRef(), isNull);
        expect(await flow.hasPendingCodeVerifier(), isFalse);
      },
    );

    test('a link without an authorization code is a bounded error', () async {
      final store = FakeSecureKeyValueStore();
      final flow = flowFor(store);
      final client = FakeRuntimeAuthClient();
      addTearDown(client.close);
      final router = ProvisionedAuthCallbackRouter(
        backend: flow.backend,
        client: client,
        flow: flow,
        links: const Stream<String>.empty(),
      );
      addTearDown(router.dispose);

      await flow.begin();
      await seedVerifier(flow);
      final outcome = await router.handle(AuthCallback.redirectUrl);

      expect(outcome.kind, AuthCallbackOutcomeKind.missingAuthorizationCode);
      expect(outcome.notice.message, authCallbackMissingCodeMessage);
      expect(client.acceptedCallbackCodes, isEmpty);
      // Nothing was exchanged, so the pending flow can still be retried.
      expect(await flow.pendingProjectRef(), projectRefA);
      expect(await flow.hasPendingCodeVerifier(), isTrue);
    });

    test('implicit-flow tokens in a link are ignored', () async {
      final store = FakeSecureKeyValueStore();
      final flow = flowFor(store);
      final client = FakeRuntimeAuthClient();
      addTearDown(client.close);
      final router = ProvisionedAuthCallbackRouter(
        backend: flow.backend,
        client: client,
        flow: flow,
        links: const Stream<String>.empty(),
      );
      addTearDown(router.dispose);

      await flow.begin();
      await seedVerifier(flow);
      final outcome = await router.handle(
        '${AuthCallback.redirectUrl}?access_token=injected-token'
        '&refresh_token=injected-refresh',
      );

      expect(outcome.kind, AuthCallbackOutcomeKind.missingAuthorizationCode);
      expect(client.acceptedCallbackCodes, isEmpty);
      expect(client.session, isNull);
    });

    test(
      'the link stream routes exactly one callback to the owning client',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        addTearDown(client.close);
        client.callbackSession = testAuthSession(authUserId: authUserIdX);
        final links = StreamController<String>.broadcast();
        addTearDown(links.close);
        final router = ProvisionedAuthCallbackRouter(
          backend: flow.backend,
          client: client,
          flow: flow,
          links: links.stream,
        );
        addTearDown(router.dispose);

        await flow.begin();
        await seedVerifier(flow);
        router.start();
        links.add(plannerCallback());
        await pumpEventQueue();

        expect(client.acceptedCallbackCodes, hasLength(1));
        expect(client.session?.user.id, authUserIdX);
      },
    );

    test(
      'a handled callback feeds the same app-lifetime session reducer',
      () async {
        final store = FakeSecureKeyValueStore();
        final flow = flowFor(store);
        final client = FakeRuntimeAuthClient();
        addTearDown(client.close);
        final session = testAuthSession(authUserId: authUserIdX);
        client.callbackSession = session;
        final repository = AuthRepository(client, provisionedAuthFlow: flow);
        final controller = AuthSessionController(repository);
        addTearDown(controller.dispose);
        await controller.start();
        final notices = <AuthCallbackNotice>[];
        final subscription = controller.callbackNotices.listen(notices.add);
        addTearDown(subscription.cancel);
        final router = ProvisionedAuthCallbackRouter(
          backend: flow.backend,
          client: client,
          flow: flow,
          links: const Stream<String>.empty(),
          onOutcome: (outcome) =>
              controller.recordAuthCallbackOutcome(outcome.notice),
        );
        addTearDown(router.dispose);

        await flow.begin();
        await seedVerifier(flow);
        await router.handle(plannerCallback());
        await pumpEventQueue();

        // The callback establishes the session through the normal Auth event
        // path, so Phase G's initial-sync baseline gate still decides when
        // normal sync may start.
        expect(controller.session?.user.id, authUserIdX);
        expect(controller.current.health, AuthSessionHealth.ready);
        expect(notices, hasLength(1));
        expect(notices.single.code, 'auth_callback_handled');
      },
    );
  });

  group('Android deep-link registration', () {
    test('registers exactly the canonical callback scheme and host', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final viewFilters =
          RegExp(r'<intent-filter>.*?</intent-filter>', dotAll: true)
              .allMatches(manifest)
              .where(
                (match) =>
                    match.group(0)!.contains('android.intent.action.VIEW'),
              )
              .toList();

      expect(viewFilters, hasLength(1));
      final filter = viewFilters.single.group(0)!;
      expect(filter, contains('android:scheme="${AuthCallback.scheme}"'));
      expect(filter, contains('android:host="${AuthCallback.host}"'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
      expect(filter, contains('android.intent.category.DEFAULT'));
      // Only the Planner scheme: no http/https interception and no path
      // restriction that would drop the callback.
      expect(
        RegExp(r'android:scheme="[^"]*"').allMatches(filter),
        hasLength(1),
      );
      expect(filter, isNot(contains('android:pathPrefix')));
      expect(filter, isNot(contains('android:pathPattern')));
    });
  });
}
