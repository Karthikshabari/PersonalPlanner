import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/sync_dao.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../data/anonymous_data_adoption.dart';
import '../../data/auth_repository.dart';
import '../../data/connection_profile_store.dart';
import '../../data/sync_repository.dart';
import '../../domain/auth_session_controller.dart';
import '../../domain/cloud_connection_lifecycle.dart';
import '../../domain/initial_sync_models.dart';
import '../../domain/password_policy.dart';
import '../../domain/runtime_backend.dart';
import '../controllers/provisioning_ui_controller.dart';
import '../../providers/runtime_backend_providers.dart';
import '../../providers/provisioning_providers.dart';
import '../../providers/sync_providers.dart';
import '../../providers/sync_settings_provider.dart';
import '../../domain/sync_models.dart';
import '../widgets/cloud_setup_preflight.dart';
import '../widgets/cloud_setup_card.dart';
import '../widgets/password_requirements.dart';
import '../widgets/sync_action_group.dart';
import '../widgets/sync_status_card.dart';
import '../widgets/sync_status_action.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    ref.listen(syncStatusProvider, (previous, next) {
      final current = next.value;
      if (current != null &&
          current.state != SyncEngineState.synced &&
          current.state != SyncEngineState.syncing &&
          current.state != SyncEngineState.pending &&
          current.state != SyncEngineState.offline &&
          current.state != SyncEngineState.refreshPaused &&
          current.state != previous?.value?.state &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current.message ?? 'Sync failed; retry scheduled.'),
          ),
        );
      }
    });
    final sessionAsync = ref.watch(authSessionProvider);
    final authController = ref.watch(authSessionControllerProvider);
    final backend = ref.watch(runtimeBackendProvider);
    final statusAsync = ref.watch(syncStatusProvider);
    final enabledAsync = ref.watch(syncEnabledProvider);
    final conflictsAsync = ref.watch(syncConflictsProvider);
    final permanentAsync = ref.watch(syncPermanentOperationsProvider);
    final quarantineAsync = ref.watch(syncQuarantinedChangesProvider);
    if (sessionAsync.hasError ||
        statusAsync.hasError ||
        enabledAsync.hasError ||
        conflictsAsync.hasError ||
        permanentAsync.hasError ||
        quarantineAsync.hasError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sync'),
          actions: const [SyncStatusAction()],
        ),
        body: ErrorPanel(
          message: friendlyErrorMessage(
            sessionAsync.error ??
                statusAsync.error ??
                enabledAsync.error ??
                conflictsAsync.error ??
                permanentAsync.error ??
                quarantineAsync.error!,
          ),
          onRetry: () {
            ref.invalidate(authSessionProvider);
            ref.invalidate(syncStatusProvider);
            ref.invalidate(syncEnabledProvider);
            ref.invalidate(syncConflictsProvider);
            ref.invalidate(syncPermanentOperationsProvider);
            ref.invalidate(syncQuarantinedChangesProvider);
          },
        ),
      );
    }
    if (!sessionAsync.hasValue ||
        !statusAsync.hasValue ||
        !enabledAsync.hasValue ||
        !conflictsAsync.hasValue ||
        !quarantineAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sync'),
          actions: const [SyncStatusAction()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final session = sessionAsync.requireValue;
    final status = statusAsync.requireValue;
    final enabled = enabledAsync.requireValue;
    final conflicts = conflictsAsync.requireValue;
    final permanentOperations = permanentAsync.value ?? const <SyncLogRow>[];
    final quarantinedChanges = quarantineAsync.requireValue;
    final adoptionSummary = session == null
        ? null
        // The compile-time developer path keeps the historical adoption card.
        // A provisioned account routes the same decision through the Phase G
        // first-sync coordinator, which only offers adoption once the cloud
        // account is proven empty.
        : backend is LegacyStaticRuntimeBackend
        ? ref.watch(anonymousDataSummaryProvider)
        : null;
    final initialSyncAsync = ref.watch(syncInitialSyncProvider);
    final initialSync = initialSyncAsync.value;
    // The Cloud Sync preference is deliberately *not* part of the post-baseline
    // surface: it belongs to the connection, applies in every account state
    // (including before the Phase G baseline exists) and must stay reachable so
    // automatic synchronization can always be switched off.
    final syncPreferenceCard = Card(
      child: SwitchListTile(
        key: const ValueKey('sync-enable-toggle'),
        title: const Text('Enable sync'),
        subtitle: const Text(
          'Disabling sync keeps the durable outbox and cursor intact.',
        ),
        value: enabled,
        onChanged: (value) =>
            ref.read(syncEnabledProvider.notifier).setEnabled(value),
      ),
    );
    List<Widget> syncStateCards() => <Widget>[
      if (conflicts.isNotEmpty)
        _ConflictCard(
          conflicts: conflicts,
          busy: _busy,
          onKeepLocal: _keepLocal,
          onKeepRemote: _keepRemote,
        ),
      if (conflicts.isNotEmpty) const SizedBox(height: 12),
      if (permanentOperations.isNotEmpty) ...[
        _PermanentFailureCard(
          operations: permanentOperations,
          busy: _busy,
          onRepair: _repairPermanentOperation,
        ),
        const SizedBox(height: 12),
      ],
      SyncStatusPanel(
        status: status,
        enabled: enabled,
        busy: _busy,
        onSyncNow: () => ref.read(syncEngineProvider)?.syncNow(),
      ),
    ];
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Sync'),
        actions: const [SyncStatusAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl,
          ),
          children: [
            if (quarantinedChanges.isNotEmpty) ...[
              _QuarantineCard(changes: quarantinedChanges),
              const SizedBox(height: 12),
            ],
            // The three runtime backends never compete for the same screen.
            //
            // local-only: provisioning is the only cloud action available.
            // provisioned ready: account connection runs against the user's own
            // project. Normal Planner data synchronization only appears after
            // the Phase G first-sync baseline is complete.
            // compile-time developer config: the legacy path below is
            // unchanged.
            if (backend is LocalOnlyRuntimeBackend) ...[
              CloudSetupCard(onUseOfflineOnly: _disconnect),
              const SizedBox(height: 12),
              const _CloudProfileHealthCard(),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.cloud_off),
                  title: Text('Offline-only mode'),
                  subtitle: Text(
                    'Personal Planner keeps working locally. Nothing is '
                    'uploaded until a cloud backend is connected.',
                  ),
                ),
              ),
            ] else if (backend is ProvisionedRuntimeBackend) ...[
              CloudSetupCard(
                onUseOfflineOnly: _disconnect,
                onStopUsingCloud: _disconnect,
              ),
              const SizedBox(height: 12),
              if (session == null)
                const _AuthForm()
              else ...[
                _CloudAccountCard(
                  session: session,
                  busy: _busy,
                  onSignOut: _signOut,
                  initialSync: initialSync,
                ),
                const SizedBox(height: 12),
                // Available before the baseline completes too, so a user can
                // always stop automatic scheduling of the first upload.
                syncPreferenceCard,
                const SizedBox(height: 12),
                if (initialSync != null && !initialSync.baselineComplete)
                  _ProvisionedFirstSyncCard(
                    status: initialSync,
                    busy: _busy,
                    syncEnabled: enabled,
                    permanentOperations: permanentOperations,
                    onRetry: _retryInitialSync,
                    onAdopt: _adoptOfflineData,
                    onKeepSeparate: _keepOfflineDataSeparate,
                    onRepair: _repairPendingInitialSyncOperation,
                    onDisconnect: _disconnect,
                  ),
                if (initialSync?.baselineComplete ?? false)
                  ...syncStateCards(),
              ],
            ] else if (session == null)
              _AuthForm()
            else ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(session.user.email ?? 'Signed-in account'),
                  subtitle: const Text(
                    'This account uses its own local SQLite database.',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Log out'),
                  ),
                ),
              ),
              if (kDebugMode && authController != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('Session diagnostics'),
                    subtitle: Text(
                      '${authController.diagnostics.length} sanitized in-memory event(s).',
                    ),
                    trailing: TextButton(
                      key: const ValueKey('auth-diagnostics-action'),
                      onPressed: () => _showAuthDiagnostics(authController),
                      child: const Text('View / export'),
                    ),
                  ),
                ),
              ],
              if (adoptionSummary != null)
                adoptionSummary.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ErrorPanel(
                      message: friendlyErrorMessage(error),
                      compact: true,
                    ),
                  ),
                  data: (summary) =>
                      summary.hasAnonymousData && !summary.keptSeparate
                      ? _AnonymousAdoptionCard(
                          summary: summary,
                          busy: _busy,
                          onImport: _importAnonymousData,
                          onKeepSeparate: _keepAnonymousDataSeparate,
                        )
                      : const SizedBox.shrink(),
                ),
              const SizedBox(height: 12),
              syncPreferenceCard,
              const SizedBox(height: 12),
              ...syncStateCards(),
              const SizedBox(height: 12),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Anonymous data is never uploaded automatically'),
                  subtitle: Text(
                    'If this account has no local data, import from offline-only '
                    'mode only after explicit confirmation.',
                  ),
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Phase G: re-run discovery of the cloud Planner state. Used by every
  /// pre-baseline state that can be retried.
  Future<void> _retryInitialSync() async {
    final coordinator = ref.read(initialSyncCoordinatorProvider);
    if (coordinator == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await coordinator.retry();
    } catch (error) {
      if (mounted) {
        setState(() => _error = safeSyncError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Phase G: import offline-only Planner data into an account whose cloud copy
  /// is proven empty. This is the same explicit, conflict-aborting adoption the
  /// compile-time developer path offers, only orchestrated under safe
  /// conditions.
  Future<void> _adoptOfflineData() async {
    final coordinator = ref.read(initialSyncCoordinatorProvider);
    if (coordinator == null) return;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import offline-only data?'),
        content: const Text(
          'This copies the offline-only records into this cloud account, then '
          'uploads them. The offline-only database is kept as a recovery copy. '
          'Any conflicting metadata or review data stops the import.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Import and upload'),
          ),
        ],
      ),
    );
    if (!mounted || choice != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await coordinator.adoptOfflineData();
      if (mounted) {
        setState(
          () => _message =
              'Offline-only data was imported. Uploading it to your cloud '
              'account.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AnonymousDataAdoptionException ? error.message : 'Import could not be completed. The offline-only data was kept.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepOfflineDataSeparate() async {
    final coordinator = ref.read(initialSyncCoordinatorProvider);
    if (coordinator == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await coordinator.keepOfflineDataSeparate();
      if (mounted) {
        setState(
          () => _message =
              'Offline-only data stays separate from this cloud account.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save that choice.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Repairs a locally parked outbox operation before the first upload
  /// completes. No remote request is made by the repair itself.
  Future<void> _repairPendingInitialSyncOperation(String operationId) async {
    final coordinator = ref.read(initialSyncCoordinatorProvider);
    if (coordinator == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await coordinator.repairPendingOperation(operationId);
      await coordinator.retry();
      if (mounted) {
        setState(
          () => _message =
              'The repaired local record was queued and the first '
              'synchronization was retried.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SyncRepairException
              ? error.message
              : 'The sync failure could not be repaired safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider)?.signOut();
    } catch (error) {
      if (mounted) setState(() => _error = safeAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stops every automatic synchronization path of the *currently open*
  /// account before any connection or session state is cleared.
  ///
  /// Nothing new is created here: `exists` is checked first so a disconnect
  /// cannot build (and start) a SyncEngine or first-sync coordinator that was
  /// not already running. A cleared session and a disabled connection also make
  /// the scope guards reject any straggling completion.
  Future<void> _suspendSync() async {
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.exists(syncEngineProvider)) {
      await container.read(syncEngineProvider)?.stop();
    }
    if (container.exists(initialSyncCoordinatorProvider)) {
      await container.read(initialSyncCoordinatorProvider)?.dispose();
    }
  }

  /// Explicit disconnect: stop sync, sign out of exactly this project, then
  /// stop resolving the stored backend while remembering its endpoint.
  ///
  /// Local Planner databases, the durable outbox and the user's Supabase
  /// project are never touched.
  ///
  /// Lifecycle correctness deliberately does not belong to this widget. The
  /// sign-out performed by the lifecycle service publishes a null session,
  /// which makes bootstrap switch the account scope to the anonymous database
  /// and dispose *this screen's* provider container — so this `State` is
  /// commonly unmounted before `disconnect` even returns. The runtime Auth
  /// teardown is therefore driven by the bootstrap-owned reloader, captured
  /// before the await and always awaited after a successful disconnect;
  /// `mounted` only guards the visual updates below.
  Future<void> _disconnect() async {
    final backend = ref.read(runtimeBackendProvider);
    if (backend is! ProvisionedRuntimeBackend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(cloudDisconnectTitle),
        content: const Text(cloudDisconnectConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('cloud-disconnect-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop using cloud'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    // Captured before the await: adopting the changed backend disposes this
    // screen's provider container, so nothing may be read from `ref` after
    // that point. `reloader` is owned by the app bootstrap (it is not scoped to
    // this container), so it stays valid for the whole transition even when
    // this widget disappears.
    final reloader = ref.read(runtimeBackendReloaderProvider);
    final lifecycle = ref.read(cloudLifecycleServiceProvider);
    final authRepository = ref.read(authRepositoryProvider);
    try {
      final result = await lifecycle.disconnect(
        backend: backend,
        stopSync: _suspendSync,
        authRepository: authRepository,
      );
      if (!result.succeeded) {
        if (mounted) {
          setState(
            () => _error = result.message ?? cloudDisconnectFailedMessage,
          );
        }
        return;
      }
      // The connection is durably disabled. The runtime Auth client and the
      // account database of this project must now be released so the local
      // Planner becomes the active scope — regardless of whether this screen
      // still exists. If this widget was unmounted by the sign-out above, the
      // bootstrap still owns the reload, so the teardown is not skipped.
      await reloader?.reload();
      if (mounted) {
        setState(
          () => _message =
              result.message ??
              'Cloud backend disconnected. Local Planner data stays on this '
                  'device.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAuthDiagnostics(AuthSessionController controller) async {
    final diagnostics = const JsonEncoder.withIndent(
      '  ',
    ).convert(controller.diagnostics.map((entry) => entry.toJson()).toList());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sanitized session diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              diagnostics,
              key: const ValueKey('auth-diagnostics-content'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: diagnostics));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Sanitized diagnostics copied.'),
                  ),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _keepAnonymousDataSeparate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(anonymousDataAdoptionProvider).keepSeparate();
      ref.invalidate(anonymousDataSummaryProvider);
      if (mounted) {
        setState(() {
          _message = 'Anonymous data remains in offline-only mode.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save that choice.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importAnonymousData() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import anonymous data?'),
        content: const Text(
          'This copies the offline-only records into this signed-in account. '
          'The offline-only database is kept as a recovery copy. Any existing '
          'metadata or review conflicts must be resolved before import.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (!choice) {
      await _keepAnonymousDataSeparate();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await ref.read(anonymousDataAdoptionProvider).adopt();
      ref.invalidate(anonymousDataSummaryProvider);
      if (mounted) {
        setState(() {
          _message =
              'Imported ${result.copiedRecords} record(s). '
              '${result.alreadyPresentRecords} already existed; sync will upload '
              'the imported records when online.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AnonymousDataAdoptionException ? error.message : 'Import could not be completed. The offline-only data was kept.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepLocal(String conflictId) => _resolveConflict(
    conflictId,
    (repository) => repository.keepLocal(conflictId),
  );

  Future<void> _keepRemote(String conflictId) => _resolveConflict(
    conflictId,
    (repository) => repository.keepRemote(conflictId),
  );

  Future<void> _resolveConflict(
    String conflictId,
    Future<void> Function(SyncRepository repository) resolve,
  ) async {
    final repository = ref.read(syncRepositoryProvider);
    if (repository == null) {
      setState(() => _error = 'Sign in and enable sync to resolve conflicts.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await resolve(repository);
      if (mounted) setState(() => _message = 'Conflict resolved.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Conflict could not be resolved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairPermanentOperation(String operationId) async {
    final repository = ref.read(syncRepositoryProvider);
    if (repository == null) {
      setState(
        () => _error = 'Sign in and enable sync to repair this failure.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.repairPermanentOperation(operationId);
      if (mounted) {
        setState(
          () => _message =
              'The repaired local record was queued. Sync it when ready.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SyncRepairException
              ? error.message
              : 'The sync failure could not be repaired safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

}

/// Explicit repair surface for an unusable stored backend profile.
///
/// An unreadable or incompatible profile deliberately resolves to local-only so
/// the Planner keeps working, but the user must still be told that a cloud
/// connection exists on this device and now needs attention. Nothing is
/// deleted: starting cloud setup replaces the unusable document only when the
/// user asks for it, and every local Planner record is untouched.
class _CloudProfileHealthCard extends ConsumerWidget {
  const _CloudProfileHealthCard();

  /// Repairing an unusable stored profile can create the user's first cloud
  /// project, so it goes through the same pre-flight as the main setup entry
  /// point and then runs the unchanged provisioning flow.
  static Future<void> _repairProfile(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCloudSetupPreflight(context);
    if (!confirmed) return;
    await ref.read(provisioningUiProvider.notifier).startSetup();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(backendProfileHealthProvider);
    if (!health.needsAttention) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const ValueKey('cloud-profile-health'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.report_problem_outlined),
                title: Text('Cloud connection needs attention'),
                subtitle: Text(
                  'A cloud backend is recorded on this device but its saved '
                  'details could not be used, so Personal Planner is running '
                  'locally. Your Planner data is intact.',
                ),
              ),
              Text(_healthDetail(health)),
              const SizedBox(height: 8),
              if (ref.watch(provisioningApiProvider) != null)
                OutlinedButton(
                  key: const ValueKey('cloud-profile-health-repair'),
                  onPressed: () => unawaited(_repairProfile(context, ref)),
                  child: const Text('Start cloud setup again'),
                )
              else
                const Text(
                  'Cloud setup is unavailable in this build, so this connection '
                  'cannot be repaired here yet.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _healthDetail(BackendProfileHealth health) => switch (health) {
    BackendProfileHealth.ok => '',
    BackendProfileHealth.unreadable =>
      'The saved cloud connection could not be read. It was not changed.',
    BackendProfileHealth.corrupt =>
      'The saved cloud connection is not a valid document. It was not changed.',
    BackendProfileHealth.unsupportedVersion =>
      'The saved cloud connection was written by a different version of '
          'Personal Planner.',
    BackendProfileHealth.tooLarge =>
      'The saved cloud connection is larger than this build accepts.',
    BackendProfileHealth.writeFailed =>
      'The cloud connection could not be saved on this device.',
  };
}

class _QuarantineCard extends StatelessWidget {
  const _QuarantineCard({required this.changes});

  final List<SyncQuarantinedChange> changes;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Sync records need review'),
            subtitle: Text(
              'A remote change could not be applied safely. Your local data is '
              'still intact and the original payload is retained for repair.',
            ),
          ),
          for (final change in changes) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_changeLabel(change)),
              subtitle: Text(
                [
                  change.diagnostic,
                  if (change.recordedAt != null)
                    'Recorded: ${change.recordedAt!.toLocal()}',
                  'Automatic replay is disabled until the payload is repaired.',
                ].join('\n'),
              ),
              trailing: IconButton(
                tooltip: 'Copy sync review details',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _copyText(change))),
              ),
            ),
            if (change != changes.last) const Divider(),
          ],
        ],
      ),
    ),
  );

  static String _changeLabel(SyncQuarantinedChange change) {
    final table = switch (change.tableName) {
      'tasks' => 'Task',
      'categories' => 'Category',
      'tags' => 'Legacy metadata',
      'subtasks' => 'Subtask',
      'recurring_rules' => 'Recurring rule',
      'task_templates' => 'Template',
      'daily_reviews' => 'Daily review',
      'weekly_reviews' => 'Weekly review',
      'timer_sessions' => 'Timer session',
      'day_contexts' => 'Day context',
      'task_tags' => 'Legacy metadata link',
      _ => 'Remote record',
    };
    final identity = change.recordId == null || change.recordId!.isEmpty
        ? 'change ${change.changeId}'
        : change.recordId!;
    return '$table · $identity';
  }

  static String _copyText(SyncQuarantinedChange change) => [
    'Personal Planner sync review',
    _changeLabel(change),
    if (change.operation != null) 'Operation: ${change.operation}',
    'Diagnostic: ${change.diagnostic}',
    'Storage key: ${change.storageKey}',
  ].join('\n');
}

class _PermanentFailureCard extends StatelessWidget {
  const _PermanentFailureCard({
    required this.operations,
    required this.busy,
    required this.onRepair,
  });

  final List<SyncLogRow> operations;
  final bool busy;
  final ValueChanged<String> onRepair;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.build_circle_outlined),
            title: Text('Sync needs a repair'),
            subtitle: Text(
              'Edit the affected record first, then queue a validated snapshot. '
              'The invalid payload will never be retried unchanged.',
            ),
          ),
          for (final operation in operations) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_operationLabel(operation)),
              subtitle: Text(
                operation.lastError?.replaceFirst(
                      SyncDao.permanentErrorPrefix,
                      '',
                    ) ??
                    'Permanent sync error',
              ),
              trailing: OutlinedButton(
                onPressed: busy ? null : () => onRepair(operation.operationId),
                child: const Text('Retry repaired record'),
              ),
            ),
            if (operation != operations.last) const Divider(),
          ],
        ],
      ),
    ),
  );

  static String _operationLabel(SyncLogRow operation) {
    final table = switch (operation.entityTableName) {
      'tasks' => 'Task',
      'categories' => 'Category',
      'tags' => 'Legacy metadata',
      'subtasks' => 'Subtask',
      'recurring_rules' => 'Recurring rule',
      'task_templates' => 'Template',
      'daily_reviews' => 'Daily review',
      'weekly_reviews' => 'Weekly review',
      'timer_sessions' => 'Timer session',
      'task_tags' => 'Legacy metadata link',
      _ => 'Record',
    };
    return '$table · ${operation.recordId}';
  }
}

class _AnonymousAdoptionCard extends StatelessWidget {
  const _AnonymousAdoptionCard({
    required this.summary,
    required this.busy,
    required this.onImport,
    required this.onKeepSeparate,
  });

  final AnonymousDataSummary summary;
  final bool busy;
  final VoidCallback onImport;
  final VoidCallback onKeepSeparate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.move_to_inbox_outlined),
            title: Text('Offline-only data found'),
            subtitle: Text(
              'Choose explicitly whether to copy it into this account. '
              'Nothing is uploaded automatically.',
            ),
          ),
          Text('${summary.anonymousRecords} record(s) available to review.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : onImport,
                child: const Text('Import anonymous data'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onKeepSeparate,
                child: const Text('Keep it separate'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflicts,
    required this.busy,
    required this.onKeepLocal,
    required this.onKeepRemote,
  });

  final List<SyncConflictRow> conflicts;
  final bool busy;
  final ValueChanged<String> onKeepLocal;
  final ValueChanged<String> onKeepRemote;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.warning_amber),
            title: Text('Conflicts need a decision'),
            subtitle: Text(
              'Both snapshots are preserved locally. Choose which one to keep.',
            ),
          ),
          for (final conflict in conflicts) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_conflictTitle(conflict)),
              subtitle: Text(
                '${_conflictDetails(conflict)}\n'
                'Expected ${conflict.expectedServerVersion ?? 'new'} · '
                'server ${conflict.actualServerVersion ?? 'deleted'}',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => onKeepLocal(conflict.id),
                  child: const Text('Keep Local'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => onKeepRemote(conflict.id),
                  child: const Text('Keep Remote'),
                ),
              ],
            ),
            if (conflict != conflicts.last) const Divider(),
          ],
        ],
      ),
    ),
  );
}

String _conflictTitle(SyncConflictRow conflict) {
  final local = _snapshotMap(conflict.localSnapshot);
  final remote = _snapshotMap(conflict.remoteSnapshot);
  final value = local ?? remote;
  final label = switch (conflict.entityTableName) {
    'tasks' => 'Task',
    'categories' => 'Category',
    'tags' => 'Legacy metadata',
    'subtasks' => 'Subtask',
    'recurring_rules' => 'Recurring rule',
    'task_templates' => 'Template',
    'daily_reviews' => 'Daily review',
    'weekly_reviews' => 'Weekly review',
    'timer_sessions' => 'Timer session',
    'task_tags' => 'Legacy metadata link',
    _ => 'Record',
  };
  final name = value == null
      ? null
      : _displayName(conflict.entityTableName, value);
  return name == null || name.isEmpty ? label : '$label · $name';
}

String _conflictDetails(SyncConflictRow conflict) {
  final local = _snapshotMap(conflict.localSnapshot);
  final remote = _snapshotMap(conflict.remoteSnapshot);
  if (local == null || remote == null) {
    return 'Local and remote snapshots are preserved.';
  }
  final fields = <String>[];
  for (final key in {...local.keys, ...remote.keys}) {
    if (const {
      'id',
      'created_at',
      'updated_at',
      'server_version',
    }.contains(key)) {
      continue;
    }
    if (local[key] == remote[key]) continue;
    fields.add(_fieldLabel(key));
  }
  final changed = fields.isEmpty
      ? 'different snapshots'
      : fields.take(4).join(', ');
  final localState = _snapshotState(local);
  final remoteState = _snapshotState(remote);
  return 'Local: $localState · Remote: $remoteState · Changed: $changed';
}

Map<String, dynamic>? _snapshotMap(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on Object {
    return null;
  }
}

String _displayName(String table, Map<String, dynamic> snapshot) {
  final value = switch (table) {
    'tasks' || 'subtasks' => snapshot['title'],
    'categories' || 'tags' || 'task_templates' => snapshot['name'],
    'recurring_rules' => snapshot['task_title'],
    'daily_reviews' => snapshot['date'],
    'weekly_reviews' => snapshot['week_start_date'],
    _ => snapshot['id'],
  };
  final text = value?.toString().trim() ?? '';
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

String _snapshotState(Map<String, dynamic> snapshot) {
  if (snapshot['deleted_at'] != null || snapshot['deleted'] == true) {
    return 'deleted';
  }
  final status = snapshot['status'];
  return status == null ? 'active' : status.toString().replaceAll('_', ' ');
}

String _fieldLabel(String key) {
  if (const {'priority', 'tags_json', 'tag_id'}.contains(key)) {
    return 'Legacy metadata';
  }
  return key
      .replaceAll('_', ' ')
      .replaceFirstMapped(
        RegExp(r'^.'),
        (match) => match.group(0)!.toUpperCase(),
      );
}

/// Connected state of a provisioned user-owned backend.
///
/// Presentation only: the account identity and the Planner-account sign-out are
/// kept in one short card, deliberately separate from cloud-project management.
/// It claims nothing about Planner data while the first synchronization is
/// unresolved, because runtime Supabase Auth being connected is not the same as
/// cloud synchronization being active.
class _CloudAccountCard extends StatelessWidget {
  const _CloudAccountCard({
    required this.session,
    required this.busy,
    required this.onSignOut,
    this.initialSync,
  });

  final Session session;
  final bool busy;
  final Future<void> Function() onSignOut;
  final InitialSyncStatus? initialSync;

  @override
  Widget build(BuildContext context) {
    final baselineComplete = initialSync?.baselineComplete ?? false;
    return Card(
      key: const ValueKey('planner-account-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Planner account'),
                subtitle: Text(
                  [
                    session.user.email ?? 'Signed-in account',
                    baselineComplete
                        ? 'Syncs your Planner data across your signed-in '
                              'devices.'
                        : 'Signed in. Cloud sync starts after the first '
                              'synchronization finishes.',
                  ].join('\n'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SyncActionGroup(
                alignment: WrapAlignment.start,
                actions: [
                  TextButton(
                    key: const ValueKey('cloud-sign-out-action'),
                    onPressed: busy ? null : onSignOut,
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase G user-facing state of the provisioned first synchronization.
///
/// States are deliberately descriptive: nothing here may claim that cloud
/// synchronization is active before the baseline exists, and the conflict state
/// offers no destructive choice.
class _ProvisionedFirstSyncCard extends StatelessWidget {
  const _ProvisionedFirstSyncCard({
    required this.status,
    required this.busy,
    required this.syncEnabled,
    required this.permanentOperations,
    required this.onRetry,
    required this.onAdopt,
    required this.onKeepSeparate,
    required this.onRepair,
    required this.onDisconnect,
  });

  final InitialSyncStatus status;
  final bool busy;
  final bool syncEnabled;
  final List<SyncLogRow> permanentOperations;
  final Future<void> Function() onRetry;
  final Future<void> Function() onAdopt;
  final Future<void> Function() onKeepSeparate;
  final ValueChanged<String> onRepair;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final waiting =
        status.phase == InitialSyncPhase.discovering ||
        status.phase == InitialSyncPhase.restoring ||
        status.phase == InitialSyncPhase.uploading ||
        status.phase == InitialSyncPhase.remoteExisting;
    return Card(
      key: const ValueKey('provisioned-first-sync'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _icon(status.phase),
                color: _color(tokens, status.phase),
              ),
              title: Text(_title(status.phase)),
              subtitle: Text(
                status.message ?? provisionedPhaseDescription(status.phase),
              ),
            ),
            if (waiting && syncEnabled) const LinearProgressIndicator(),
            if (!syncEnabled) ...[
              const SizedBox(height: 8),
              const Text(
                'Cloud Sync is switched off, so nothing is uploaded or '
                'restored. Turn it back on to continue.',
              ),
            ],
            if (status.phase == InitialSyncPhase.adoptionRequired) ...[
              const SizedBox(height: 12),
              SyncActionGroup(
                alignment: WrapAlignment.start,
                actions: [
                  FilledButton(
                    key: const ValueKey('first-sync-import-offline'),
                    onPressed: busy ? null : onAdopt,
                    child: const Text('Import offline data and upload'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : onKeepSeparate,
                    child: const Text('Keep offline data separate'),
                  ),
                ],
              ),
            ],
            if (status.phase == InitialSyncPhase.recoveryRequired) ...[
              const SizedBox(height: 12),
              const Text(
                'Personal Planner will not merge or overwrite either copy. '
                'Retrying asks the cloud account again; disconnecting stops '
                'using this cloud backend and keeps every local record.',
              ),
              const SizedBox(height: 8),
              SyncActionGroup(
                alignment: WrapAlignment.start,
                actions: [
                  FilledButton(
                    key: const ValueKey('first-sync-recovery-retry'),
                    onPressed: busy || !syncEnabled ? null : onRetry,
                    child: const Text('Retry cloud setup'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('first-sync-recovery-disconnect'),
                    onPressed: busy ? null : onDisconnect,
                    child: const Text(cloudDisconnectTitle),
                  ),
                ],
              ),
            ],
            if (permanentOperations.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'A local record needs a repair before it can be uploaded. '
                'Nothing is ever retried unchanged.',
              ),
              for (final operation in permanentOperations) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(operation.recordId),
                  subtitle: Text(
                    operation.lastError?.replaceFirst(
                          SyncDao.permanentErrorPrefix,
                          '',
                        ) ??
                        'Permanent sync error',
                  ),
                  trailing: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => onRepair(operation.operationId),
                    child: const Text('Retry repaired record'),
                  ),
                ),
              ],
            ],
            if (status.phase != InitialSyncPhase.adoptionRequired &&
                status.phase != InitialSyncPhase.recoveryRequired) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('first-sync-retry'),
                onPressed: busy || waiting || !syncEnabled ? null : onRetry,
                child: const Text('Retry cloud setup'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _title(InitialSyncPhase phase) => switch (phase) {
    InitialSyncPhase.unresolved => 'Cloud setup pending',
    InitialSyncPhase.discovering => 'Checking cloud Planner data',
    InitialSyncPhase.remoteExisting => 'Cloud Planner data found',
    InitialSyncPhase.restoring => 'Restoring from your cloud account',
    InitialSyncPhase.remoteEmpty => 'Cloud account is empty',
    InitialSyncPhase.adoptionRequired => 'Offline-only data found',
    InitialSyncPhase.uploading => 'Uploading your local Planner data',
    InitialSyncPhase.conflict => 'Local and cloud data both exist',
    InitialSyncPhase.recoveryRequired => 'This cloud account needs recovery',
    InitialSyncPhase.retryable => 'Cloud setup needs a retry',
    InitialSyncPhase.complete => 'Cloud synchronization ready',
  };

  static IconData _icon(InitialSyncPhase phase) => switch (phase) {
    InitialSyncPhase.discovering ||
    InitialSyncPhase.restoring ||
    InitialSyncPhase.uploading => Icons.cloud_sync_outlined,
    InitialSyncPhase.remoteExisting => Icons.cloud_download_outlined,
    InitialSyncPhase.remoteEmpty => Icons.cloud_queue,
    InitialSyncPhase.adoptionRequired => Icons.move_to_inbox_outlined,
    InitialSyncPhase.conflict => Icons.warning_amber,
    InitialSyncPhase.recoveryRequired => Icons.health_and_safety_outlined,
    InitialSyncPhase.retryable => Icons.sync_problem,
    InitialSyncPhase.unresolved ||
    InitialSyncPhase.complete => Icons.cloud_queue,
  };

  static Color? _color(AppThemeTokens tokens, InitialSyncPhase phase) =>
      switch (phase) {
        InitialSyncPhase.conflict => tokens.pending,
        InitialSyncPhase.recoveryRequired => tokens.error,
        InitialSyncPhase.retryable => tokens.error,
        _ => tokens.info,
      };
}

class _AuthForm extends ConsumerStatefulWidget {
  const _AuthForm();

  @override
  ConsumerState<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<_AuthForm> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool registering = false;
  bool busy = false;
  bool _passwordVisible = false;
  String? error;
  String? passwordError;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Local validation only gates a submission the guaranteed policy already
    // knows cannot pass; Supabase stays the final authority.
    final canSubmit =
        !busy && (!registering || PlannerPasswordPolicy.isSatisfied(password.text));
    return Card(
      key: const ValueKey('planner-account-form'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Planner account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              registering
                  ? 'Create an account to sync your Planner data across your '
                        'devices.'
                  : 'Sign in to sync your Planner data across your devices.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('sync-email'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('sync-password'),
              controller: password,
              obscureText: !_passwordVisible,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {
                if (passwordError != null) passwordError = null;
              }),
              onSubmitted: (_) {
                if (canSubmit) unawaited(_submit());
              },
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: passwordError,
                suffixIcon: IconButton(
                  key: const ValueKey('sync-password-visibility'),
                  tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
            ),
            if (registering) ...[
              const SizedBox(height: AppSpacing.sm),
              PasswordRequirementsIndicator(password: password.text),
            ],
            const SizedBox(height: AppSpacing.lg),
            SyncActionGroup(
              alignment: WrapAlignment.start,
              actions: [
                FilledButton(
                  key: const ValueKey('sync-submit-action'),
                  onPressed: canSubmit ? _submit : null,
                  child: Text(registering ? 'Register' : 'Log in'),
                ),
              ],
            ),
            TextButton(
              key: const ValueKey('sync-register-toggle'),
              onPressed: busy
                  ? null
                  : () => setState(() {
                      registering = !registering;
                      error = null;
                      passwordError = null;
                      message = null;
                    }),
              child: Text(
                registering
                    ? 'Already have an account? Log in'
                    : 'Need an account? Register',
              ),
            ),
            if (message != null) Text(message!),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const _AuthCallbackNotice(),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final passwordValue = password.text;
    if (registering && !PlannerPasswordPolicy.isSatisfied(passwordValue)) {
      // Obviously invalid locally: never spend a Supabase request on it.
      setState(() {
        passwordError = null;
        error = null;
        message = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      passwordError = null;
      message = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (auth == null) throw StateError('Sync is not configured');
      final response = registering
          ? await auth.signUp(email.text, passwordValue)
          : await auth.signIn(email.text, passwordValue);
      if (registering && response.session == null && mounted) {
        setState(
          () => message =
              'Check your email to confirm the account. Confirmation works on '
              'any device: open the link, then log in here with the same '
              'email and password.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      // A password the server rejected belongs on the password field, never in
      // the generic error line.
      if (isPasswordPolicyFailure(error)) {
        setState(() {
          passwordError = passwordPolicyErrorMessage();
          this.error = null;
        });
      } else {
        setState(() => this.error = safeAuthError(error));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// Bounded, sanitized failure of the most recent provisioned Auth callback.
///
/// A rejected callback never changes the session or the active scope; it only
/// explains why the email confirmation did not sign this device in. Rendered
/// next to the sign-in form so the user has an explicit retry path.
class _AuthCallbackNotice extends ConsumerWidget {
  const _AuthCallbackNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(authCallbackNoticeProvider).value;
    if (notice == null || notice.handled || notice.message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(notice.message, key: const ValueKey('auth-callback-notice')),
    );
  }
}
