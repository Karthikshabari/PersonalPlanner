import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/cloud_connection_lifecycle.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/domain/runtime_backend.dart';

import '../../helpers/runtime_auth_fakes.dart';

/// Durable representation of "this device stopped using this backend".
void main() {
  BackendConnectionProfile ready({
    bool disconnected = false,
    int generation = 4,
  }) => BackendConnectionProfile(
    profileId: 'profile-1',
    generation: generation,
    state: ProvisioningState.ready,
    createdAt: runtimeAuthTestClock,
    updatedAt: runtimeAuthTestClock,
    projectRef: projectRefA,
    projectUrl: 'https://$projectRefA.supabase.co',
    publishableKey: publishableKeyA,
    provisioningTransactionId: '0123456789abcdef0123456789abcdef',
    connectionDisabled: disconnected,
  );

  group('profile document', () {
    test('a connected profile stays byte-compatible with earlier documents', () {
      final json = ready().toJson();

      expect(json.containsKey('connection_disabled'), isFalse);
      expect(
        BackendConnectionProfile.fromJson(json).connectionDisabled,
        isFalse,
      );
    });

    test('a disconnection is durable and reversible', () {
      final disconnected = ready(disconnected: true);
      final json = disconnected.toJson();
      expect(json['connection_disabled'], isTrue);

      final restored = BackendConnectionProfile.fromJson(json);
      expect(restored.connectionDisabled, isTrue);
      expect(restored.projectRef, projectRefA);
      expect(restored.publishableKey, publishableKeyA);
      expect(restored.canReconnect, isTrue);
      expect(isReconnectableProfile(restored), isTrue);

      final reconnected = restored.copyWith(
        generation: restored.generation + 1,
        connectionDisabled: false,
      );
      expect(reconnected.connectionDisabled, isFalse);
      expect(isReconnectableProfile(reconnected), isFalse);
      // The identity of the backend never changes across the transition.
      restored.validateReplacement(reconnected);
    });

    test('only a verified backend can be remembered as disconnected', () {
      expect(
        () => BackendConnectionProfile(
          profileId: 'profile-1',
          generation: 1,
          state: ProvisioningState.authorizationPending,
          createdAt: runtimeAuthTestClock,
          updatedAt: runtimeAuthTestClock,
          provisioningTransactionId: '0123456789abcdef0123456789abcdef',
          connectionDisabled: true,
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });
  });

  group('runtime resolution', () {
    test('a disconnected profile never becomes a runtime backend', () {
      expect(
        ProvisionedRuntimeBackend.tryFromProfile(ready(disconnected: true)),
        isNull,
      );
      expect(
        resolveRuntimeBackend(
          legacyStaticConfigured: false,
          legacyStaticUrl: '',
          legacyStaticPublishableKey: '',
          profile: ready(disconnected: true),
        ),
        isA<LocalOnlyRuntimeBackend>(),
      );
    });

    test('a connected profile still resolves to its provisioned backend', () {
      final resolved = resolveRuntimeBackend(
        legacyStaticConfigured: false,
        legacyStaticUrl: '',
        legacyStaticPublishableKey: '',
        profile: ready(),
      );

      expect(resolved, isA<ProvisionedRuntimeBackend>());
      expect(
        (resolved as ProvisionedRuntimeBackend).projectRef,
        projectRefA,
      );
    });

    test('compile-time configuration still wins over a remembered backend', () {
      final resolved = resolveRuntimeBackend(
        legacyStaticConfigured: true,
        legacyStaticUrl: 'https://developer.supabase.co',
        legacyStaticPublishableKey: publishableKeyA,
        profile: ready(disconnected: true),
      );

      expect(resolved, isA<LegacyStaticRuntimeBackend>());
    });
  });
}
