import 'dart:async';

import 'package:personal_planner/features/sync/data/backend_project_probe.dart';
import 'package:personal_planner/features/sync/data/provisioning_client.dart';
import 'package:personal_planner/features/sync/domain/backend_connection_profile.dart';
import 'package:personal_planner/features/sync/domain/provisioning_coordinator.dart';
import 'package:personal_planner/features/sync/domain/provisioning_state.dart';
import 'package:personal_planner/features/sync/providers/provisioning_providers.dart';

const testTransactionId = '0123456789abcdef0123456789abcdef';
const testProjectRef = 'abcdefghijklmnopqrst';
const testPublishableKey = 'sb_publishable_CuLX_Y3xWuD0cuItKbm-Xw_NJMQ84zu';
final testNow = DateTime.utc(2026, 9, 16, 12);
final testAuthorizationUrl = Uri.parse(
  'https://api.supabase.com/v1/oauth/authorize?state=transaction.secret',
);

BackendConnectionProfile testProfile(
  ProvisioningState state, {
  String? projectRef,
  String? errorCode,
  String transactionId = testTransactionId,
}) => BackendConnectionProfile(
  profileId: 'profile-1',
  generation: 1,
  state: state,
  createdAt: testNow,
  updatedAt: testNow,
  provisioningTransactionId: transactionId,
  projectRef: projectRef,
  projectUrl: projectRef == null ? null : 'https://$projectRef.supabase.co',
  publishableKey: state == ProvisioningState.ready ? testPublishableKey : null,
  errorCode: errorCode,
);

ProvisioningAttempt testAttempt(
  ProvisioningState state, {
  bool hasCapability = true,
  String? projectRef,
  String? errorCode,
}) => ProvisioningAttempt(
  profile: testProfile(state, projectRef: projectRef, errorCode: errorCode),
  transactionId: testTransactionId,
  hasCapability: hasCapability,
);

ProvisioningResult testInProgress(
  ProvisioningState state, {
  String? projectRef,
  String? errorCode,
}) => ProvisioningResult(
  outcome: ProvisioningOutcome.inProgress,
  profile: testProfile(state, projectRef: projectRef, errorCode: errorCode),
);

ProvisioningResult testOrganizations(
  List<ProvisioningOrganization> organizations, {
  ProvisioningState state = ProvisioningState.authorizationPending,
}) => ProvisioningResult(
  outcome: ProvisioningOutcome.inProgress,
  profile: testProfile(state),
  organizations: organizations,
);

/// Scriptable stand-in for the real C2 coordinator.
class FakeProvisioningApi implements ProvisioningApi {
  FakeProvisioningApi({this.attempt});

  ProvisioningAttempt? attempt;
  final List<String> calls = <String>[];
  final List<({String slug, String projectName})> selections =
      <({String slug, String projectName})>[];
  int startAttemptCount = 0;

  ProvisioningResult startResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult refreshResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult organizationsResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult selectResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult createResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult migrateResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );
  ProvisioningResult verifyResult = const ProvisioningResult(
    outcome: ProvisioningOutcome.inProgress,
  );

  /// Scripted result of starting a Management authorization.
  ManagementStartResult startManagementResult = const ManagementStartResult(
    outcome: ManagementStartOutcome.authorizationReady,
    authorizationUrl: null,
  );

  /// Scripted result of completing the Management project check.
  ManagementCheckResult completeManagementResult = const ManagementCheckResult(
    outcome: ManagementCheckOutcome.exists,
  );

  /// Scripted result of revoking Management access.
  ManagementRevokeResult revokeManagementResult = const ManagementRevokeResult(
    outcome: ManagementRevokeOutcome.nothingHeld,
  );

  /// Scripted answer for "is a Management authorization in flight?".
  bool pendingManagementAuthorization = false;

  /// Scripted answer for the authoritative host probe.
  bool remoteMissingRecorded = false;

  /// When set, [selectOrganization] waits until it completes.
  Completer<void>? holdSelect;

  @override
  Future<ProvisioningAttempt?> loadAttempt() async {
    calls.add('loadAttempt');
    return attempt;
  }

  @override
  Future<ProvisioningResult> startAttempt() async {
    calls.add('startAttempt');
    startAttemptCount += 1;
    attempt ??= testAttempt(ProvisioningState.authorizationPending);
    return startResult;
  }

  @override
  Future<ProvisioningResult> refresh() async {
    calls.add('refresh');
    return refreshResult;
  }

  @override
  Future<ProvisioningResult> listOrganizations() async {
    calls.add('listOrganizations');
    return organizationsResult;
  }

  @override
  Future<ProvisioningResult> selectOrganization({
    required String organizationSlug,
    required String projectName,
  }) async {
    calls.add('selectOrganization');
    selections.add((slug: organizationSlug, projectName: projectName));
    final hold = holdSelect;
    if (hold != null) await hold.future;
    return selectResult;
  }

  @override
  Future<ProvisioningResult> createOrContinueProject() async {
    calls.add('createOrContinueProject');
    return createResult;
  }

  @override
  Future<ProvisioningResult> migrate() async {
    calls.add('migrate');
    return migrateResult;
  }

  @override
  Future<ProvisioningResult> verify() async {
    calls.add('verify');
    return verifyResult;
  }

  @override
  Future<ManagementStartResult> startManagementCheck() async {
    calls.add('startManagementCheck');
    return startManagementResult;
  }

  @override
  Future<ManagementCheckResult> completeManagementCheck() async {
    calls.add('completeManagementCheck');
    return completeManagementResult;
  }

  @override
  Future<ManagementRevokeResult> revokeManagementAccess() async {
    calls.add('revokeManagementAccess');
    return revokeManagementResult;
  }

  @override
  Future<bool> hasPendingManagementAuthorization() async {
    calls.add('hasPendingManagementAuthorization');
    return pendingManagementAuthorization;
  }

  @override
  Future<bool> markRemoteMissing() async {
    calls.add('markRemoteMissing');
    return remoteMissingRecorded;
  }
}

class FakeBrowserLauncher implements BrowserLauncher {
  final List<Uri> opened = <Uri>[];
  bool succeeds = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return succeeds;
  }
}

/// Scriptable stand-in for the bounded project-host probe.
class FakeProjectProbe implements BackendProjectProbe {
  BackendProjectProbeResult result = BackendProjectProbeResult.indeterminate;
  final List<Uri> probed = <Uri>[];

  @override
  Duration get timeout => const Duration(seconds: 1);

  @override
  Future<BackendProjectProbeResult> probe(Uri projectUrl) async {
    probed.add(projectUrl);
    return result;
  }

  @override
  void close() {}
}
