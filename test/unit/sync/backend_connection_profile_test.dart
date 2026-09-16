import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

const _projectRef = 'abcdefghijklmnopqrst';
const _projectUrl = 'https://abcdefghijklmnopqrst.supabase.co';
const _publishableKey = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';
const _transactionId = '0123456789abcdef0123456789abcdef';

final _createdAt = DateTime.utc(2026, 9, 16, 12);

BackendConnectionProfile _localOnly({int generation = 1}) =>
    BackendConnectionProfile.localOnly(
      profileId: 'profile-a',
      createdAt: _createdAt,
      generation: generation,
    );

BackendConnectionProfile _ready({
  int generation = 4,
  DateTime? updatedAt,
  String? projectRef = _projectRef,
  String? projectUrl = _projectUrl,
  String? publishableKey = _publishableKey,
}) => BackendConnectionProfile(
  profileId: 'profile-a',
  generation: generation,
  state: ProvisioningState.ready,
  createdAt: _createdAt,
  updatedAt: updatedAt ?? _createdAt,
  projectRef: projectRef,
  projectUrl: projectUrl,
  publishableKey: publishableKey,
  installationId: 'installation-0001',
  compatibility: BackendCompatibility(
    protocolVersion: 2,
    payloadVersions: const [1, 2],
  ),
  provisioningTransactionId: _transactionId,
);

void main() {
  group('local-only profile', () {
    test('carries no backend or provisioning data', () {
      final profile = _localOnly();

      expect(profile.state, ProvisioningState.localOnly);
      expect(profile.projectRef, isNull);
      expect(profile.projectUrl, isNull);
      expect(profile.publishableKey, isNull);
      expect(profile.installationId, isNull);
      expect(profile.compatibility, isNull);
      expect(profile.resumeState, isNull);
      expect(profile.errorCode, isNull);
      expect(profile.provisioningTransactionId, isNull);
    });

    test('rejects every optional backend field', () {
      final base = {
        'profileId': 'profile-a',
        'generation': 1,
        'state': ProvisioningState.localOnly,
        'createdAt': _createdAt,
        'updatedAt': _createdAt,
      };

      expect(
        () => BackendConnectionProfile(
          profileId: base['profileId']! as String,
          generation: 1,
          state: ProvisioningState.localOnly,
          createdAt: _createdAt,
          updatedAt: _createdAt,
          projectRef: _projectRef,
          projectUrl: _projectUrl,
          publishableKey: _publishableKey,
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendConnectionProfile(
          profileId: 'profile-a',
          generation: 1,
          state: ProvisioningState.localOnly,
          createdAt: _createdAt,
          updatedAt: _createdAt,
          provisioningTransactionId: _transactionId,
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendConnectionProfile(
          profileId: 'profile-a',
          generation: 1,
          state: ProvisioningState.localOnly,
          createdAt: _createdAt,
          updatedAt: _createdAt,
          errorCode: 'cancelled_by_user',
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });
  });

  group('ready profile', () {
    test('round trips through JSON with only client-safe fields', () {
      final profile = _ready();

      final json = profile.toJson();
      expect(
        json.keys.toSet(),
        equals(<String>{
          'format_version',
          'profile_id',
          'generation',
          'state',
          'project_ref',
          'project_url',
          'publishable_key',
          'installation_id',
          'compatibility',
          'provisioning_transaction_id',
          'created_at',
          'updated_at',
        }),
      );
      expect(json['format_version'], plannerBackendProfileFormatVersion);
      expect(json['state'], 'ready');
      expect(
        json['compatibility'],
        equals({
          'protocol_version': 2,
          'payload_versions': [1, 2],
        }),
      );

      final restored = BackendConnectionProfile.fromJson(json);
      expect(restored, equals(profile));
      expect(restored.hashCode, equals(profile.hashCode));
      expect(restored.compatibility, equals(profile.compatibility));
    });

    test('requires projectRef, projectUrl and publishableKey', () {
      expect(
        () => _ready(publishableKey: null),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => _ready(projectUrl: null),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => _ready(projectRef: null),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('toString never echoes the publishable key', () {
      final profile = _ready();

      expect(profile.toString(), contains('abcdefghijklmnopqrst'));
      expect(profile.toString(), isNot(contains('sb_publishable_')));
    });
  });

  group('field validation', () {
    test('rejects malformed project refs', () {
      for (final ref in <String>[
        '',
        'short',
        'ABCDEFGHIJKLMNOPQRST',
        'abcdefghijklmnopqrstu',
        'abcdefghijklmnopqrs-',
        'abcdefghijklmnopqrs1',
      ]) {
        expect(
          () => _ready(projectRef: ref, projectUrl: null),
          throwsA(isA<BackendProfileValidationException>()),
          reason: ref,
        );
      }
    });

    test('rejects non-https, mismatched and non-canonical project URLs', () {
      for (final url in <String>[
        'http://abcdefghijklmnopqrst.supabase.co',
        'https:///path',
        'https://otherrefxxxxxxxxxxxx.supabase.co',
        'https://abcdefghijklmnopqrst.supabase.co:8443',
        'https://user:pass@abcdefghijklmnopqrst.supabase.co',
        'https://abcdefghijklmnopqrst.supabase.co/rest/v1',
        'https://abcdefghijklmnopqrst.supabase.co?apikey=1',
        'https://abcdefghijklmnopqrst.supabase.co#fragment',
        'https://PASTE_YOUR_PROJECT_REF.supabase.co',
      ]) {
        expect(
          () => _ready(projectUrl: url),
          throwsA(isA<BackendProfileValidationException>()),
          reason: url,
        );
      }
    });

    test('requires a projectRef before a projectUrl', () {
      expect(
        () => BackendConnectionProfile(
          profileId: 'profile-a',
          generation: 1,
          state: ProvisioningState.projectWaiting,
          createdAt: _createdAt,
          updatedAt: _createdAt,
          projectUrl: _projectUrl,
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('accepts publishable keys and rejects secret-shaped ones', () {
      final accepted = _ready();
      expect(accepted.publishableKey, _publishableKey);

      for (final key in <String>[
        'sb_secret_abcdefghijklmnopqrstuvwxyz',
        'service_role_abcdefghijklmnopqrstuvwxyz',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature',
        'sbp_abcdefghijklmnopqrstuvwxyz',
        'sba_abcdefghijklmnopqrstuvwxyz',
        'PASTE_YOUR_PUBLISHABLE_KEY',
        'sb_publishable_short',
      ]) {
        expect(
          () => _ready(publishableKey: key),
          throwsA(isA<BackendProfileValidationException>()),
          reason: key,
        );
      }
    });

    test('rejects credential shapes in any persisted string field', () {
      expect(
        () => _ready().copyWith(
          installationId: 'eyJhbGciOiJIUzI1NiJ9.payload.signature',
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => _localOnly().copyWith(errorCode: 'access_token'),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () =>
            _ready(projectRef: 'abcdefghijklmnopqrst')
                .copyWith(profileId: 'sb_secret_abcdefghijklmnopqrst'),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('accepts sanitized error codes and rejects raw diagnostics', () {
      final profile = _ready().copyWith(errorCode: 'project_creation_failed');
      expect(profile.errorCode, 'project_creation_failed');
      expect(
        BackendConnectionProfile.fromJson(profile.toJson()).errorCode,
        'project_creation_failed',
      );

      for (final code in <String>[
        'HTTP 502: upstream failure',
        '{"error":"project_creation_failed"}',
        'Error: stack trace',
        'UPPER_CASE',
      ]) {
        expect(
          () => _localOnly().copyWith(errorCode: code),
          throwsA(isA<BackendProfileValidationException>()),
          reason: code,
        );
      }
    });

    test('validates compatibility metadata', () {
      expect(
        () => BackendCompatibility(protocolVersion: 0, payloadVersions: [1]),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendCompatibility(protocolVersion: 2, payloadVersions: []),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendCompatibility(protocolVersion: 2, payloadVersions: [2, 1]),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendCompatibility(protocolVersion: 2, payloadVersions: [1, 1]),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final compatibility = BackendCompatibility(
        protocolVersion: 2,
        payloadVersions: [1, 2],
      );
      expect(
        BackendCompatibility.fromJson(compatibility.toJson()),
        equals(compatibility),
      );
      expect(
        () => BackendCompatibility.fromJson({
          'protocol_version': 2,
          'payload_versions': ['2'],
        }),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => BackendCompatibility.fromJson({
          'protocol_version': 2,
          'payload_versions': [2],
          'extra': true,
        }),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('normalizes timestamps to UTC and rejects inverted ranges', () {
      final local = DateTime(2026, 9, 16, 18, 30);
      final profile = _localOnly().copyWith(createdAt: local, updatedAt: local);

      expect(profile.createdAt.isUtc, isTrue);
      expect(profile.createdAt, equals(local.toUtc()));
      expect(profile.updatedAt, equals(local.toUtc()));

      expect(
        () => _localOnly().copyWith(
          updatedAt: _createdAt.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('rejects impossible resume states', () {
      expect(
        () => _localOnly().copyWith(resumeState: ProvisioningState.localOnly),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => _localOnly().copyWith(resumeState: ProvisioningState.ready),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () =>
            _localOnly().copyWith(resumeState: ProvisioningState.terminalError),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final resumable = _localOnly().copyWith(
        state: ProvisioningState.projectReconciliationRequired,
        provisioningTransactionId: _transactionId,
        resumeState: ProvisioningState.projectCreating,
      );
      expect(resumable.resumeState, ProvisioningState.projectCreating);
      expect(
        BackendConnectionProfile.fromJson(resumable.toJson()).resumeState,
        ProvisioningState.projectCreating,
      );
    });
  });

  group('serialization failures', () {
    test('rejects unknown format versions without reinterpreting them', () {
      final json = _ready().toJson()..['format_version'] = 99;

      expect(
        () => BackendConnectionProfile.fromJson(json),
        throwsA(isA<UnsupportedBackendProfileFormatException>()),
      );
      final jsonWithoutVersion = _ready().toJson()..remove('format_version');
      expect(
        () => BackendConnectionProfile.fromJson(jsonWithoutVersion),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('rejects unknown fields and wrong types', () {
      final unknownField = _ready().toJson()
        ..['management_token'] = 'should-not-be-here';
      expect(
        () => BackendConnectionProfile.fromJson(unknownField),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final missingState = _ready().toJson()..remove('state');
      expect(
        () => BackendConnectionProfile.fromJson(missingState),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final wrongGeneration = _ready().toJson()..['generation'] = '4';
      expect(
        () => BackendConnectionProfile.fromJson(wrongGeneration),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final unknownState = _ready().toJson()..['state'] = 'backend_resolving';
      expect(
        () => BackendConnectionProfile.fromJson(unknownState),
        throwsA(isA<BackendProfileValidationException>()),
      );

      final unknownTimestamp = _ready().toJson()..['created_at'] = 'yesterday';
      expect(
        () => BackendConnectionProfile.fromJson(unknownTimestamp),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });
  });

  group('copyWith', () {
    test('keeps omitted fields and clears explicitly null ones', () {
      final profile = _ready().copyWith(errorCode: 'verification_failed');

      final progressed = profile.copyWith(generation: 5);
      expect(progressed.errorCode, 'verification_failed');
      expect(progressed.generation, 5);
      expect(progressed.state, ProvisioningState.ready);
      expect(progressed.projectRef, _projectRef);

      final cleared = progressed.copyWith(errorCode: null);
      expect(cleared.errorCode, isNull);
      expect(cleared.projectRef, _projectRef);
    });
  });

  group('validateReplacement', () {
    test('requires a strictly increasing generation', () {
      final stored = _localOnly(generation: 3);
      final sameGeneration = stored.copyWith();

      expect(
        () => stored.validateReplacement(sameGeneration),
        throwsA(isA<BackendProfileValidationException>()),
      );
      expect(
        () => stored.validateReplacement(stored.copyWith(generation: 2)),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('rejects transitions the Worker cannot produce', () {
      final stored = _localOnly();
      final skippedAhead = stored.copyWith(
        generation: 2,
        state: ProvisioningState.ready,
        projectRef: _projectRef,
        projectUrl: _projectUrl,
        publishableKey: _publishableKey,
      );

      expect(
        () => stored.validateReplacement(skippedAhead),
        throwsA(isA<ProvisioningStateTransitionException>()),
      );
      expect(
        () => stored.validateReplacement(
          stored.copyWith(
            generation: 2,
            state: ProvisioningState.authorizationPending,
          ),
        ),
        returnsNormally,
      );
    });

    test('keeps project identity immutable for the same profile', () {
      final stored = _ready(generation: 4);
      final otherProjectRef = 'zyxwvutsrqponmlkjihg';
      final retargeted = stored.copyWith(
        generation: 5,
        projectRef: otherProjectRef,
        projectUrl: 'https://$otherProjectRef.supabase.co',
      );

      expect(
        () => stored.validateReplacement(retargeted),
        throwsA(isA<BackendProfileValidationException>()),
      );
    });

    test('allows a new profile identity to replace the stored connection', () {
      final stored = _ready(generation: 4);
      final replacement = stored.copyWith(
        profileId: 'profile-b',
        generation: 5,
        state: ProvisioningState.authorizationPending,
        projectRef: null,
        projectUrl: null,
        publishableKey: null,
        installationId: null,
        compatibility: null,
        provisioningTransactionId: null,
        resumeState: null,
        errorCode: null,
      );

      expect(() => stored.validateReplacement(replacement), returnsNormally);
    });
  });
}
