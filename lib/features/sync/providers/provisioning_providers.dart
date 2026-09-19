import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/provisioning_config.dart';
import '../data/backend_project_probe.dart';
import '../data/cloud_lifecycle_service.dart';
import '../data/connection_profile_store.dart';
import '../data/management_attempt_store.dart';
import '../data/provisioning_capability_store.dart';
import '../data/provisioning_client.dart';
import '../data/secure_session_storage.dart';
import '../domain/provisioning_coordinator.dart';

/// External-browser handoff for the Supabase authorization page.
///
/// Deliberately tiny so tests can capture the URI instead of opening a browser.
abstract interface class BrowserLauncher {
  /// Opens [url] in the user's normal browser; false when the platform refused.
  Future<bool> open(Uri url);
}

class UrlLauncherBrowserLauncher implements BrowserLauncher {
  const UrlLauncherBrowserLauncher();

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A failed hand-off must never destroy the provisioning transaction.
      return false;
    }
  }
}

final browserLauncherProvider = Provider<BrowserLauncher>(
  (ref) => const UrlLauncherBrowserLauncher(),
);

/// Durable, non-secret provisioning profile storage (Phase B).
final connectionProfileStoreProvider = Provider<ConnectionProfileStore>(
  (ref) => ConnectionProfileStore(),
);

/// Secure storage for the short-lived provisioning capability (Phase C2).
final provisioningCapabilityStoreProvider =
    Provider<ProvisioningCapabilityStore>(
      (ref) => SecureProvisioningCapabilityStore(),
    );

/// Explicit disconnect/reconnect operations of the provisioned connection.
///
/// Uses the same durable stores as provisioning (the profile file and the
/// secure provisioning-capability namespace) so a lifecycle action and a
/// provisioning attempt can never disagree about which backend is stored.
final cloudLifecycleServiceProvider = Provider<CloudLifecycleService>((ref) {
  return CloudLifecycleService(
    profileStore: ref.watch(connectionProfileStoreProvider),
    capabilityStore: ref.watch(provisioningCapabilityStoreProvider),
  );
});

/// Control-plane client, or null when this build has no provisioning base URL.
///
/// Nothing here is constructed at app startup: the providers are only read when
/// the Sync settings screen actually builds the cloud-setup card.
final provisioningClientProvider = Provider<ProvisioningClient?>((ref) {
  final base = ProvisioningConfig.baseUri;
  if (base == null) return null;
  return ProvisioningClient(
    baseUrl: base,
    transport: IoProvisioningTransport(),
  );
});

/// The narrow provisioning surface the setup presentation layer depends on.
///
/// Keeping the UI behind this interface means the presentation tests never need
/// a real Worker, and it documents exactly which coordinator actions the UI is
/// allowed to drive.
abstract interface class ProvisioningApi {
  Future<ProvisioningAttempt?> loadAttempt();

  Future<ProvisioningResult> startAttempt();

  Future<ProvisioningResult> refresh();

  Future<ProvisioningResult> listOrganizations();

  Future<ProvisioningResult> selectOrganization({
    required String organizationSlug,
    required String projectName,
  });

  Future<ProvisioningResult> createOrContinueProject();

  Future<ProvisioningResult> migrate();

  Future<ProvisioningResult> verify();

  /// Reads the Supabase Management authorization retained for this backend.
  Future<ManagementStartResult> startManagementCheck();

  /// Completes the in-flight Supabase Management authorization.
  Future<ManagementCheckResult> completeManagementCheck();

  /// Revokes Personal Planner's Supabase Management authorization.
  Future<ManagementRevokeResult> revokeManagementAccess();

  /// True when a Management authorization is still in flight on this device.
  Future<bool> hasPendingManagementAuthorization();

  /// Records authoritative "the project host answered 404" evidence.
  Future<bool> markRemoteMissing();
}

class _CoordinatorProvisioningApi implements ProvisioningApi {
  const _CoordinatorProvisioningApi(this._coordinator);

  final ProvisioningCoordinator _coordinator;

  @override
  Future<ProvisioningAttempt?> loadAttempt() => _coordinator.loadAttempt();

  @override
  Future<ProvisioningResult> startAttempt() => _coordinator.startAttempt();

  @override
  Future<ProvisioningResult> refresh() => _coordinator.refresh();

  @override
  Future<ProvisioningResult> listOrganizations() =>
      _coordinator.listOrganizations();

  @override
  Future<ProvisioningResult> selectOrganization({
    required String organizationSlug,
    required String projectName,
  }) => _coordinator.selectOrganization(
    organizationSlug: organizationSlug,
    projectName: projectName,
  );

  @override
  Future<ProvisioningResult> createOrContinueProject() =>
      _coordinator.createOrContinueProject();

  @override
  Future<ProvisioningResult> migrate() => _coordinator.migrate();

  @override
  Future<ProvisioningResult> verify() => _coordinator.verify();

  @override
  Future<ManagementStartResult> startManagementCheck() =>
      _coordinator.startManagementCheck();

  @override
  Future<ManagementCheckResult> completeManagementCheck() =>
      _coordinator.completeManagementCheck();

  @override
  Future<ManagementRevokeResult> revokeManagementAccess() =>
      _coordinator.revokeManagementAccess();

  @override
  Future<bool> hasPendingManagementAuthorization() =>
      _coordinator.hasPendingManagementAuthorization();

  @override
  Future<bool> markRemoteMissing() => _coordinator.markRemoteMissing();
}

/// Coordinator-backed provisioning API, or null when the control plane URL is
/// not configured for this build.
final provisioningApiProvider = Provider<ProvisioningApi?>((ref) {
  final client = ref.watch(provisioningClientProvider);
  if (client == null) return null;
  return _CoordinatorProvisioningApi(
    ProvisioningCoordinator(
      profileStore: ref.watch(connectionProfileStoreProvider),
      capabilityStore: ref.watch(provisioningCapabilityStoreProvider),
      managementAttemptStore: ref.watch(managementAttemptStoreProvider),
      client: client,
    ),
  );
});

/// Secure storage for the single in-flight Management authorization.
final managementAttemptStoreProvider = Provider<ManagementAttemptStore>(
  (ref) => ManagementAttemptStore(storage: FlutterSecureKeyValueStore()),
);

/// Bounded probe of the user's own Supabase project host.
final backendProjectProbeProvider = Provider<BackendProjectProbe>((ref) {
  final probe = BackendProjectProbe();
  ref.onDispose(probe.close);
  return probe;
});

/// Polling interval used only while the cloud-setup card is on screen.
final provisioningPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);
