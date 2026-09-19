// Hosted provisioning E2E harness (developer/test only, not production UI).
//
// It drives the REAL Phase C2 stack against the REAL deployed provisioning
// Worker over HTTPS, using the real OS-backed secure storage and an isolated
// on-disk profile location. It is staged so a human can complete Supabase
// Management OAuth in a browser between runs, which also proves durable resume
// across a real process restart.
//
// Usage (each stage is a separate process):
//   flutter test integration_test/provisioning_e2e_test.dart -d linux \
//     --dart-define=PROVISIONING_BASE_URL=<worker base url> \
//     --dart-define=E2E_STAGE=start|resume|provision \
//     --dart-define=E2E_PROFILE_DIR=/tmp/personal_planner_provisioning_e2e_<id> \
//     --dart-define=E2E_PROJECT_NAME=personal-planner-e2e-<id>
//
// Secrets are never printed: the provisioning capability and the publishable
// key are reported as present/absent and redacted summaries only.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/features/sync/data/connection_profile_store.dart';
import 'package:personal_planner/features/sync/data/management_attempt_store.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';

const _stage = String.fromEnvironment('E2E_STAGE');
const _profileDirectory = String.fromEnvironment('E2E_PROFILE_DIR');
const _projectName = String.fromEnvironment('E2E_PROJECT_NAME');
const _protectedProjectName = 'Planner';
const _organizationName = 'Ks_Planner';

const _maxDriveSteps = 60;
const _driveInterval = Duration(seconds: 15);

void _log(String message) => debugPrint('E2E: $message');

Never _fail(String message) {
  _log('FAILED: $message');
  throw TestFailure(message);
}

ProvisioningClient _client() => ProvisioningClient.fromConfig();

ConnectionProfileStore _profileStore() =>
    ConnectionProfileStore(directory: Directory(_profileDirectory));

SecureProvisioningCapabilityStore _capabilityStore() =>
    SecureProvisioningCapabilityStore();

ProvisioningCoordinator _coordinator() => ProvisioningCoordinator(
  profileStore: _profileStore(),
  capabilityStore: _capabilityStore(),
  managementAttemptStore: ManagementAttemptStore(
    storage: FlutterSecureKeyValueStore(),
  ),
  client: _client(),
);

String _redactKey(String value) => value.length <= 24
    ? '${value.substring(0, 12)}…(len ${value.length})'
    : '${value.substring(0, 24)}…(len ${value.length})';

void _validateConfiguration() {
  if (_stage.isEmpty) _fail('E2E_STAGE must be start, resume, or provision');
  if (_profileDirectory.isEmpty) _fail('E2E_PROFILE_DIR must be set');
  if (_projectName.isEmpty) _fail('E2E_PROJECT_NAME must be set');
  Directory(_profileDirectory).createSync(recursive: true);
  _log('stage=$_stage');
  _log('isolated profile directory=$_profileDirectory');
  _log('disposable project name=$_projectName');
  _log('protected project (never touched)=$_protectedProjectName');
  _log('intended organization=$_organizationName');
}

Future<void> _stageStart() async {
  final coordinator = _coordinator();
  final existing = await coordinator.loadAttempt();
  if (existing != null) {
    _fail(
      'an attempt already exists (transaction ${existing.transactionId}, '
      'state ${existing.state.wireName}); refusing to create a second one',
    );
  }

  final result = await coordinator.startAttempt();
  if (result.outcome != ProvisioningOutcome.inProgress) {
    _fail('startAttempt returned ${result.outcome.name}: ${result.message}');
  }
  final profile = result.profile!;
  final transactionId = profile.provisioningTransactionId!;
  _log('transaction created: $transactionId');
  _log('transaction state: ${profile.state.wireName}');
  _log('profile file: $_profileDirectory/$plannerBackendProfileFileName');

  final capability = await _capabilityStore().read(
    transactionId: transactionId,
  );
  if (capability == null) _fail('the provisioning capability was not stored');
  _log('capability stored in secure storage: yes (value not printed)');

  final contents = File('$_profileDirectory/$plannerBackendProfileFileName')
      .readAsStringSync();
  if (contents.contains(capability)) {
    _fail('the provisioning capability leaked into the profile document');
  }
  _log('capability absent from profile document: yes');

  final url = result.authorizationUrl!;
  _log('authorization url prepared: ${url.scheme}://${url.host}${url.path}');
  debugPrint('E2E_AUTHORIZATION_URL=$url');
}

/// Read-only diagnostic: reports the durable attempt and whether its
/// provisioning capability is still present. Never prints the capability.
Future<void> _stageStatus() async {
  final attempt = await _coordinator().loadAttempt();
  if (attempt == null) {
    _log('no durable provisioning attempt in $_profileDirectory');
    debugPrint('E2E_STATUS=local_only');
    return;
  }
  _log('transaction=${attempt.transactionId}');
  _log('authoritative state=${attempt.state.wireName}');
  _log('error code=${attempt.profile.errorCode ?? 'none'}');
  _log('projectRef=${attempt.profile.projectRef ?? 'none'}');
  _log('capability present=${attempt.hasCapability ? 'yes' : 'no'}');
  debugPrint('E2E_STATUS=status');
}

Future<void> _stageResume() async {
  final coordinator = _coordinator();
  final attempt = await coordinator.loadAttempt();
  if (attempt == null) {
    _fail('no durable attempt found in $_profileDirectory');
  }
  _log('resumed transaction: ${attempt.transactionId}');
  _log('durable state before refresh: ${attempt.state.wireName}');
  _log(
    'capability found in secure storage: ${attempt.hasCapability ? 'yes' : 'no'}',
  );
  if (!attempt.hasCapability) {
    _fail(
      'the provisioning capability is missing; this attempt cannot continue',
    );
  }

  final refreshed = await coordinator.refresh();
  _log('state after refresh: ${refreshed.profile?.state.wireName}');
  if (refreshed.outcome == ProvisioningOutcome.stale) {
    _fail('the attempt was superseded by a newer one');
  }
  final transactionAfter = refreshed.profile!.provisioningTransactionId;
  if (transactionAfter != attempt.transactionId) {
    _fail('the transaction id changed across restart');
  }
  _log('same transaction across process restart: yes');

  // The Worker keeps `authorization_pending` after the OAuth callback (that
  // callback stores credentials; only selection advances the state), so the
  // authoritative check for "authorized" is whether the Worker can now use its
  // stored Management credential to list organizations.
  final discovery = await coordinator.listOrganizations();
  if (discovery.outcome == ProvisioningOutcome.restartRequired) {
    debugPrint('E2E_STATUS=awaiting_oauth');
    _log(
      'the Worker reports Management authorization is not complete yet '
      '(${discovery.message}); authorize in the browser and re-run resume',
    );
    return;
  }
  if (discovery.outcome != ProvisioningOutcome.inProgress) {
    _fail(
      'organization discovery returned ${discovery.outcome.name}: '
      '${discovery.message}',
    );
  }
  _log('organizations returned: ${discovery.organizations.length}');
  for (final organization in discovery.organizations) {
    _log(
      'organization: slug=${organization.slug} name=${organization.name} '
      'id=${organization.id}',
    );
  }
  final match = discovery.organizations
      .where((organization) => organization.name == _organizationName)
      .toList();
  if (match.length != 1) {
    _fail(
      'exactly one $_organizationName organization was expected, found ${match.length}',
    );
  }
  _log('selected organization slug for E2E: ${match.single.slug}');
  debugPrint('E2E_ORGANIZATION_SLUG=${match.single.slug}');
  debugPrint('E2E_STATUS=awaiting_confirmation');
}

Future<void> _stageProvision() async {
  final coordinator = _coordinator();
  final attempt = await coordinator.loadAttempt();
  if (attempt == null) _fail('no durable attempt found in $_profileDirectory');

  final discovery = await coordinator.listOrganizations();
  if (discovery.outcome != ProvisioningOutcome.inProgress) {
    _fail(
      'organization discovery returned ${discovery.outcome.name}: '
      '${discovery.message}',
    );
  }
  final match = discovery.organizations
      .where((organization) => organization.name == _organizationName)
      .toList();
  if (match.length != 1) {
    _fail(
      'exactly one $_organizationName organization was expected, found ${match.length}',
    );
  }
  _log(
    'creating disposable project $_projectName under '
    '$_organizationName (${match.single.slug}); '
    '$_protectedProjectName is untouched',
  );

  final selection = await coordinator.selectOrganization(
    organizationSlug: match.single.slug,
    projectName: _projectName,
  );
  if (selection.outcome == ProvisioningOutcome.restartRequired) {
    debugPrint('E2E_STATUS=awaiting_oauth');
    _log('Management authorization is not complete yet; authorize and re-run');
    return;
  }
  if (selection.outcome == ProvisioningOutcome.stale) {
    _fail('the attempt was superseded during organization selection');
  }
  _log('state after selection: ${selection.profile?.state.wireName}');
  if (selection.outcome != ProvisioningOutcome.inProgress) {
    _fail(
      'organization selection returned ${selection.outcome.name}: '
      '${selection.message}',
    );
  }

  final seenStates = <String>[];
  for (var step = 0; step < _maxDriveSteps; step += 1) {
    final current = await coordinator.loadAttempt();
    if (current == null) _fail('the durable attempt disappeared');
    final state = current.state;
    if (seenStates.isEmpty || seenStates.last != state.wireName) {
      seenStates.add(state.wireName);
      _log('state: ${state.wireName}');
    }

    switch (state) {
      case ProvisioningState.ready:
        _log('state sequence: ${seenStates.join(' -> ')}');
        await _verifyReady(await coordinator.refresh(), current.transactionId);
        return;
      case ProvisioningState.terminalError:
        _fail(
          'provisioning reached terminal_error '
          '(${current.profile.errorCode ?? 'unknown'})',
        );
      case ProvisioningState.expired:
        _fail(
          'the provisioning transaction expired; a new attempt is required',
        );
      case ProvisioningState.authorizationPending:
        debugPrint('E2E_STATUS=awaiting_oauth');
        _log(
          'OAuth has not completed yet; authorize in the browser and re-run',
        );
        return;
      default:
        break;
    }

    final ProvisioningResult stepResult;
    if (state == ProvisioningState.verifying) {
      stepResult = await coordinator.verify();
    } else if (state == ProvisioningState.projectWaiting ||
        state == ProvisioningState.migrating ||
        state == ProvisioningState.migrationReconciliationRequired) {
      stepResult = await coordinator.migrate();
    } else {
      stepResult = await coordinator.createOrContinueProject();
    }
    _log(
      'step ${step + 1}: ${state.wireName} -> '
      '${stepResult.outcome.name}'
      '${stepResult.message == null ? '' : ' (${stepResult.message})'}',
    );
    if (stepResult.outcome == ProvisioningOutcome.stale) {
      _fail('the attempt was superseded during provisioning');
    }
    if (stepResult.outcome == ProvisioningOutcome.capabilityMissing) {
      _fail('the provisioning capability is missing before ready');
    }
    if (stepResult.outcome == ProvisioningOutcome.ready) {
      _log('state sequence: ${seenStates.join(' -> ')}');
      await _verifyReady(stepResult, current.transactionId);
      return;
    }
    await Future<void>.delayed(_driveInterval);
  }
  _fail('provisioning did not reach ready within the bounded drive budget');
}

Future<void> _verifyReady(
  ProvisioningResult readyResult,
  String transactionId,
) async {
  final snapshot = readyResult.snapshot;
  if (snapshot == null || !snapshot.isReady) {
    _fail('the coordinator reported ready without a ready snapshot');
  }
  final config = snapshot.runtimeConfig;
  if (config == null) {
    _fail('the ready snapshot has no runtime configuration');
  }

  // §30: the Worker's runtimeConfig is validated by the Phase B model, not by
  // a second, weaker check in this harness.
  final now = DateTime.now().toUtc();
  final validated = BackendConnectionProfile(
    profileId: 'e2e-runtime-config-validation',
    generation: 1,
    state: ProvisioningState.ready,
    createdAt: now,
    updatedAt: now,
    projectRef: config.projectRef,
    projectUrl: config.projectUrl,
    publishableKey: config.publishableKey,
  );
  _log('runtimeConfig accepted by BackendConnectionProfile: yes');

  final stored = await _profileStore().read();
  if (stored == null) _fail('no persisted profile was found after ready');
  if (stored.state != ProvisioningState.ready) {
    _fail('the persisted profile is not ready (${stored.state.wireName})');
  }
  if (stored.projectRef != validated.projectRef ||
      stored.projectUrl != validated.projectUrl ||
      stored.publishableKey != validated.publishableKey) {
    _fail(
      'the persisted profile does not match the validated runtime configuration',
    );
  }
  final projectRef = stored.projectRef!;
  final projectUrl = stored.projectUrl!;
  final publishableKey = stored.publishableKey!;
  _log('persisted profile state: ready');
  _log('projectRef: $projectRef');
  _log('projectUrl: $projectUrl');
  _log('publishable key: ${_redactKey(publishableKey)}');
  _log('profile generation: ${stored.generation}');
  _log(
    'provisioning transaction retained: ${stored.provisioningTransactionId}',
  );
  if (projectUrl != 'https://$projectRef.supabase.co') {
    _fail('the canonical project URL does not match the project ref');
  }

  final contents = File('$_profileDirectory/$plannerBackendProfileFileName')
      .readAsStringSync();
  for (final forbidden in <String>[
    'capability',
    'accessToken',
    'tokenCiphertext',
    'oauthVerifier',
    'management',
    'sb_secret_',
  ]) {
    if (contents.contains(forbidden)) {
      _fail('the persisted profile contains forbidden content: $forbidden');
    }
  }
  _log('persisted profile contains no capability or Management material: yes');

  // §32: verify capability cleanup directly against secure storage rather than
  // inferring it from coordinator success.
  final capability = await _capabilityStore().read(
    transactionId: transactionId,
  );
  if (capability != null) {
    _fail('the provisioning capability was not deleted after ready');
  }
  _log('provisioning capability after ready: deleted');

  debugPrint('E2E_PROJECT_REF=$projectRef');
  debugPrint('E2E_STATUS=ready');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hosted provisioning E2E stage',
    timeout: const Timeout(Duration(minutes: 30)),
    (tester) async {
      await tester.runAsync(() async {
        _validateConfiguration();
        switch (_stage) {
          case 'start':
            await _stageStart();
          case 'resume':
            await _stageResume();
          case 'provision':
            await _stageProvision();
          case 'status':
            await _stageStatus();
          default:
            _fail('unknown E2E_STAGE: $_stage');
        }
      });
    },
  );
}
