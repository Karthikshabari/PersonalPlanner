import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/planner_account_scope.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';

import '../../helpers/provisioning_fakes.dart' show testProfile, testNow;
import '../../helpers/runtime_auth_fakes.dart';

RuntimeBackend _resolveWith({BackendConnectionProfile? profile}) =>
    resolveRuntimeBackend(
      legacyStaticConfigured: false,
      legacyStaticUrl: '',
      legacyStaticPublishableKey: '',
      profile: profile,
    );

void main() {
  group('runtime backend resolution', () {
    test('nothing configured resolves to local-only', () {
      final backend = _resolveWith();

      expect(backend, isA<LocalOnlyRuntimeBackend>());
      expect(backend.authNamespaces, isNull);
      expect(backend.plannerDataSyncEndpoint, isNull);
      expect(backend.allowsPlannerDataSync, isFalse);
      expect(backend.accountScopeFor(authUserIdX), isNull);
    });

    test('compile-time configuration wins over a ready profile', () {
      final backend = resolveRuntimeBackend(
        legacyStaticConfigured: true,
        legacyStaticUrl: 'https://developer.supabase.co',
        legacyStaticPublishableKey: publishableKeyA,
        profile: testReadyProfile(),
      );

      expect(backend, isA<LegacyStaticRuntimeBackend>());
      final endpoint = backend.plannerDataSyncEndpoint!;
      expect(endpoint.url, 'https://developer.supabase.co');
      expect(endpoint.publishableKey, publishableKeyA);
      // The stored profile never competes: no project-scoped namespace appears.
      expect(backend.authNamespaces!.isProjectScoped, isFalse);
      expect(
        backend.accountScopeFor(authUserIdX),
        PlannerAccountScope.legacyStatic(authUserIdX),
      );
    });

    test('a ready profile resolves to the provisioned backend', () {
      final backend = _resolveWith(profile: testReadyProfile());

      expect(backend, isA<ProvisionedRuntimeBackend>());
      final provisioned = backend as ProvisionedRuntimeBackend;
      expect(provisioned.projectRef, projectRefA);
      expect(provisioned.projectUrl, 'https://$projectRefA.supabase.co');
      expect(provisioned.publishableKey, publishableKeyA);
      expect(provisioned.profileId, 'profile-1');
      expect(provisioned.generation, 1);
    });

    test('the provisioned backend is project-scoped for Auth', () {
      final backend = _resolveWith(
        profile: testReadyProfile(),
      ) as ProvisionedRuntimeBackend;

      final namespaces = backend.authNamespaces;
      expect(namespaces.projectRef, projectRefA);
      expect(
        namespaces.sessionKey,
        'personal_planner.supabase.$projectRefA.session',
      );
      expect(
        namespaces.pkceKey('code-verifier'),
        'personal_planner.supabase.$projectRefA.pkce.code-verifier',
      );
      expect(
        backend.accountScopeFor(authUserIdX),
        PlannerAccountScope.provisioned(
          projectRef: projectRefA,
          authUserId: authUserIdX,
        ),
      );
      expect(backend.accountScopeFor('account-a'), isNull);
    });

    test('the provisioned backend exposes its endpoint behind the Phase G gate', () {
      final backend = _resolveWith(profile: testReadyProfile());

      // Phase G: the client-safe endpoint exists, but normal synchronization is
      // gated by the durable first-sync baseline in the sync providers.
      final endpoint = backend.plannerDataSyncEndpoint!;
      expect(endpoint.url, 'https://$projectRefA.supabase.co');
      expect(endpoint.publishableKey, publishableKeyA);
      expect(backend.allowsPlannerDataSync, isTrue);
      expect(backend, isA<ProvisionedRuntimeBackend>());
    });

    test('the same project ref at a newer generation is a different value', () {
      final first = ProvisionedRuntimeBackend.tryFromProfile(
        testReadyProfile(),
      )!;
      final second = ProvisionedRuntimeBackend.tryFromProfile(
        testReadyProfile(generation: 2),
      )!;

      expect(first == second, isFalse);
    });

    test('only a READY profile produces a provisioned backend', () {
      for (final state in ProvisioningState.values) {
        // `localOnly` carries no project data at all and is asserted
        // separately below.
        if (state == ProvisioningState.ready ||
            state == ProvisioningState.localOnly) {
          continue;
        }
        final profile = BackendConnectionProfile(
          profileId: 'profile-1',
          generation: 1,
          state: state,
          createdAt: testNow,
          updatedAt: testNow,
          projectRef: projectRefA,
          projectUrl: 'https://$projectRefA.supabase.co',
        );

        expect(
          ProvisionedRuntimeBackend.tryFromProfile(profile),
          isNull,
          reason: '${state.wireName} must not reach runtime Auth',
        );
        expect(
          _resolveWith(profile: profile),
          isA<LocalOnlyRuntimeBackend>(),
          reason: '${state.wireName} must stay local-only',
        );
      }
    });

    test('a partial ready profile is rejected', () {
      // A profile the model itself refuses to build cannot exist, so this
      // covers the defensive conversion instead: a local-only profile has no
      // project data at all and must not produce a client.
      final localOnly = BackendConnectionProfile.localOnly(
        profileId: 'profile-1',
        createdAt: testNow,
      );

      expect(ProvisionedRuntimeBackend.tryFromProfile(localOnly), isNull);
      expect(
        ProvisionedRuntimeBackend.tryFromProfile(
          testProfile(
            ProvisioningState.authorizationPending,
            projectRef: projectRefA,
          ),
        ),
        isNull,
      );
    });
  });
}
