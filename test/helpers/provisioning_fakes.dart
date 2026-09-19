import 'dart:async';

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
  ManagementAuthorizationResult managementStatusResult =
      const ManagementAuthorizationResult(
        outcome: ManagementAuthorizationOutcome.completed,
        status: ProvisioningManagementAuthorization(
          // The normal state of a ready backend: the Worker released the
          // authorization as soon as provisioning finished.
          authorized: false,
          pending: false,
        ),
      );
  ManagementAuthorizationResult startManagementResult =
      const ManagementAuthorizationResult(
        outcome: ManagementAuthorizationOutcome.completed,
        authorizationUrl: null,
      );
  ManagementAuthorizationResult revokeManagementResult =
      const ManagementAuthorizationResult(
        outcome: ManagementAuthorizationOutcome.completed,
      );

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
  Future<ManagementAuthorizationResult> managementAuthorizationStatus() async {
    calls.add('managementAuthorizationStatus');
    return managementStatusResult;
  }

  @override
  Future<ManagementAuthorizationResult> startManagementAuthorization() async {
    calls.add('startManagementAuthorization');
    return startManagementResult;
  }

  @override
  Future<ManagementAuthorizationResult> revokeManagementAuthorization() async {
    calls.add('revokeManagementAuthorization');
    return revokeManagementResult;
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
