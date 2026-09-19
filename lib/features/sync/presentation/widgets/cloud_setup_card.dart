import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/runtime_backend_providers.dart';
import '../../providers/provisioning_providers.dart';
import '../controllers/provisioning_ui_controller.dart';

/// Settings → Sync card for the user-owned Supabase setup flow.
///
/// Presentation only: it drives [ProvisioningUiController] and never talks to
/// the Worker, secure storage or the Durable Object directly.
class CloudSetupCard extends ConsumerStatefulWidget {
  const CloudSetupCard({super.key});

  @override
  ConsumerState<CloudSetupCard> createState() => _CloudSetupCardState();
}

class _CloudSetupCardState extends ConsumerState<CloudSetupCard>
    with WidgetsBindingObserver {
  ProvisioningUiController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Loading and resume happen when the user actually opens this screen; there
    // is no provisioning work at application startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(provisioningUiProvider.notifier);
      _controller = controller;
      unawaited(controller.startWatching());
    });
  }

  Future<void> _openProjectDashboard(String projectRef) async {
    final opened = await ref
        .read(browserLauncherProvider)
        .open(supabaseProjectDashboardUrl(projectRef));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The Supabase dashboard could not be opened.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Presentation polling must never outlive the screen.
    _controller?.stopWatching();
    super.dispose();
  }

  /// Resumes provisioning when the app comes back from the browser.
  ///
  /// Returning from the authorization browser is the normal path even when the
  /// automatic deep link did not fire (the user pressed the fallback button, or
  /// the platform refused the scheme). Resuming on this lifecycle event means
  /// the user never has to press "Check authorization" themselves.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final controller = _controller;
    if (controller == null) return;
    if (controller.current?.phase ==
        ProvisioningUiPhase.waitingForAuthorization) {
      unawaited(controller.checkAuthorization());
      return;
    }
    // A re-authorization that is still outstanding is also resolved by coming
    // back to the app, even when the automatic deep link did not fire.
    if (controller.current?.managementAuthorization?.pending ?? false) {
      unawaited(controller.refreshManagementAuthorization());
    }
  }

  /// Confirms, then performs, real revocation of Personal Planner's Supabase
  /// management access.
  ///
  /// Revocation is server-side: the Worker calls Supabase's own revocation
  /// endpoint. Nothing local is deleted, and neither the Supabase project nor
  /// the Planner account session is affected.
  Future<void> _confirmSupabaseAccessDisconnect(
    ProvisioningUiController controller,
  ) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Supabase access?'),
        content: const Text(
          'This revokes Personal Planner\'s Supabase authorization.\n\n'
          '• Your Supabase project and its data are not deleted.\n'
          '• Your Planner account and session are not affected.\n'
          '• Local Planner data stays on this device.\n'
          '• You can re-authorize later from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('cloud-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect Supabase access'),
          ),
        ],
      ),
    );
    if (choice != true) return;
    await controller.disconnectSupabaseAccess();
  }

  @override
  Widget build(BuildContext context) {
    // A backend that finishes provisioning while the Planner is running needs
    // its runtime Auth client, and the app bootstrap owns client lifecycle.
    // Ask it to adopt the newly stored profile; this is a no-op when the active
    // backend already matches or when compile-time configuration wins.
    ref.listen(provisioningUiProvider, (previous, next) {
      final becameReady =
          (next.value?.isReady ?? false) &&
          !(previous?.value?.isReady ?? false);
      if (!becameReady) return;
      final pending = ref.read(runtimeBackendReloaderProvider)?.reload();
      if (pending != null) unawaited(pending);
    });
    return ref
        .watch(provisioningUiProvider)
        .when(
          loading: () => const _CloudCard(
            icon: Icons.cloud_queue,
            title: 'Cloud sync',
            body: 'Checking cloud setup…',
          ),
          error: (error, _) => _CloudCard(
            icon: Icons.cloud_off,
            title: 'Cloud setup unavailable',
            body: friendlyErrorMessage(error),
            actions: <Widget>[
              TextButton(
                onPressed: () => ref.invalidate(provisioningUiProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
          data: _buildPhase,
        );
  }

  Widget _buildPhase(ProvisioningUiState state) {
    final controller = ref.read(provisioningUiProvider.notifier);
    final busy = state.busy;
    final debugDetail = _debugDetail(state);

    switch (state.phase) {
      case ProvisioningUiPhase.unavailable:
        return _CloudCard(
          icon: Icons.cloud_off,
          title: 'Cloud sync',
          body: state.message ?? cloudSetupUnavailableMessage,
          debugDetail: debugDetail,
        );

      case ProvisioningUiPhase.localOnly:
        return _CloudCard(
          icon: Icons.cloud_outlined,
          title: 'Cloud sync',
          body: cloudSetupLocalOnlyBody,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-enable-action'),
              onPressed: busy ? null : controller.startSetup,
              child: const Text('Enable Cloud Sync'),
            ),
          ],
        );

      case ProvisioningUiPhase.waitingForAuthorization:
        return _CloudCard(
          icon: Icons.verified_user_outlined,
          title: 'Authorize Supabase',
          body: state.message ?? cloudSetupWaitingMessage,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-check-authorization'),
              onPressed: busy ? null : controller.checkAuthorization,
              child: const Text('Check authorization'),
            ),
            if (state.authorizationUrlAvailable)
              TextButton(
                key: const ValueKey('cloud-open-authorization'),
                onPressed: busy ? null : controller.openAuthorizationPage,
                child: const Text('Open authorization page'),
              ),
            TextButton(
              key: const ValueKey('cloud-start-again'),
              onPressed: busy ? null : controller.startAgain,
              child: const Text('Start setup again'),
            ),
          ],
        );

      case ProvisioningUiPhase.organizationSelection:
        final organizations = state.organizations;
        return _CloudCard(
          icon: Icons.account_tree_outlined,
          title: 'Choose a Supabase organization',
          body: organizations.isEmpty
              ? 'No Supabase organization was returned for this account.'
              : 'Personal Planner will create one project in the organization '
                    'you choose. That project belongs to you.',
          debugDetail: debugDetail,
          busy: busy,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final organization in organizations)
                ListTile(
                  key: ValueKey<String>(
                    'cloud-organization-${organization.slug}',
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  selected:
                      state.selectedOrganization?.slug == organization.slug,
                  leading: Icon(
                    state.selectedOrganization?.slug == organization.slug
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(organization.name),
                  subtitle: organization.slug == organization.name
                      ? null
                      : Text(organization.slug),
                  onTap: busy
                      ? null
                      : () => controller.selectOrganization(organization),
                ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-continue-action'),
              onPressed: busy || state.selectedOrganization == null
                  ? null
                  : controller.continueSetup,
              child: const Text('Continue'),
            ),
          ],
        );

      case ProvisioningUiPhase.provisioning:
        return _CloudCard(
          icon: Icons.cloud_sync_outlined,
          title: 'Setting up your cloud backend',
          body: '${_stageLabel(state.stage)}\n\n$cloudSetupLeaveHint',
          debugDetail: debugDetail,
          busy: busy,
          content: const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey('cloud-check-progress'),
              onPressed: busy ? null : controller.advance,
              child: const Text('Check progress'),
            ),
          ],
        );

      case ProvisioningUiPhase.retryableError:
        return _CloudCard(
          icon: Icons.cloud_off,
          title: 'Cloud setup paused',
          body: state.message ?? cloudSetupRetryableMessage,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-retry-action'),
              onPressed: busy ? null : controller.retry,
              child: const Text('Retry'),
            ),
            // Explicit escape hatch: some retryable failures can never succeed
            // on this transaction (for example a missing OAuth scope that was
            // granted after this attempt was authorized). Start Again abandons
            // this local attempt and asks the coordinator for a brand-new
            // transaction; it never deletes a Supabase project.
            TextButton(
              key: const ValueKey('cloud-start-again'),
              onPressed: busy ? null : controller.startAgain,
              child: const Text('Start Again'),
            ),
            if (state.authorizationUrlAvailable)
              TextButton(
                key: const ValueKey('cloud-open-authorization'),
                onPressed: busy ? null : controller.openAuthorizationPage,
                child: const Text('Open authorization page'),
              ),
          ],
        );

      case ProvisioningUiPhase.restartRequired:
        return _CloudCard(
          icon: Icons.restart_alt,
          title: 'Setup session ended',
          body: state.message ?? cloudSetupRestartMessage,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-restart-action'),
              onPressed: busy ? null : controller.startAgain,
              child: const Text('Start Setup Again'),
            ),
          ],
        );

      case ProvisioningUiPhase.terminalError:
        return _CloudCard(
          icon: Icons.error_outline,
          title: "Cloud setup couldn't be completed",
          body: state.message ?? cloudSetupTerminalMessage,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-restart-action'),
              onPressed: busy ? null : controller.startAgain,
              child: const Text('Start Again'),
            ),
          ],
        );

      case ProvisioningUiPhase.ready:
        final profile = state.readyProfile;
        final projectRef = profile?.projectRef;
        final management = state.managementAuthorization;
        return _CloudCard(
          icon: Icons.cloud_done_outlined,
          title: 'Cloud storage ready',
          // A lifecycle action on this card (re-authorize, disconnect Supabase
          // access) reports its result here, so the ready body gives way to the
          // explicit outcome message.
          body: state.message ?? cloudSetupReadyBody,
          debugDetail: debugDetail,
          busy: busy,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Cloud project'),
                subtitle: Text(
                  projectRef == null
                      ? 'This user-owned Supabase project is ready.'
                      : 'Your own Supabase project is ready.',
                ),
                trailing: projectRef == null
                    ? null
                    : TextButton(
                        key: const ValueKey('cloud-open-dashboard'),
                        onPressed: busy
                            ? null
                            : () =>
                                  unawaited(_openProjectDashboard(projectRef)),
                        child: const Text('Open Supabase Dashboard'),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key_outlined),
                title: const Text('Advanced · Supabase access'),
                subtitle: const Text(cloudSetupSupabaseAccessBody),
                isThreeLine: true,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  OutlinedButton(
                    key: const ValueKey('cloud-reauthorize-action'),
                    onPressed: busy
                        ? null
                        : controller.reauthorizeSupabaseAccess,
                    child: const Text('Re-authorize Supabase'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('cloud-revoke-action'),
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _confirmSupabaseAccessDisconnect(controller),
                          ),
                    child: const Text('Disconnect Supabase access'),
                  ),
                ],
              ),
              if (management != null) ...[
                const SizedBox(height: 8),
                Text(
                  management.authorized
                      ? 'Personal Planner currently holds management access to '
                            'this project.'
                      : management.pending
                      ? cloudSetupSupabaseAccessPending
                      : management.releaseUnconfirmed
                      ? cloudSetupSupabaseAccessReleased
                      : 'Personal Planner does not hold management access to '
                            'this project.',
                  key: const ValueKey('cloud-management-status'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );

      case ProvisioningUiPhase.disconnected:
        final profile = state.readyProfile;
        final projectRef = profile?.projectRef;
        return _CloudCard(
          icon: Icons.cloud_off_outlined,
          title: 'Cloud storage disconnected',
          body: state.message ?? cloudSetupDisconnectedBody,
          debugDetail: debugDetail,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-reconnect-action'),
              onPressed: busy ? null : controller.reconnect,
              child: const Text('Reconnect to this project'),
            ),
            if (projectRef != null)
              TextButton(
                key: const ValueKey('cloud-open-dashboard'),
                onPressed: busy
                    ? null
                    : () => unawaited(_openProjectDashboard(projectRef)),
                child: const Text('Open Supabase dashboard'),
              ),
          ],
        );
    }
  }

  String _stageLabel(CloudSetupStage? stage) => switch (stage) {
    CloudSetupStage.preparingProject => 'Preparing your cloud project',
    CloudSetupStage.waitingForProject => 'Waiting for your cloud project',
    CloudSetupStage.installingPlannerSchema => 'Installing Planner schema',
    CloudSetupStage.verifyingCloudStorage => 'Verifying cloud storage',
    null => 'Setting up your cloud backend',
  };

  /// Debug-only, non-secret identifiers: never credentials or keys.
  String? _debugDetail(ProvisioningUiState state) {
    if (!kDebugMode) return null;
    final parts = <String>[
      if (state.transactionId != null) 'transaction ${state.transactionId}',
      if (state.errorCode != null) 'code ${state.errorCode}',
      if (state.readyProfile?.projectRef != null)
        'project ${state.readyProfile!.projectRef}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _CloudCard extends StatelessWidget {
  const _CloudCard({
    required this.icon,
    required this.title,
    required this.body,
    this.content,
    this.actions = const <Widget>[],
    this.busy = false,
    this.debugDetail,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? content;
  final List<Widget> actions;
  final bool busy;
  final String? debugDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            ?content,
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
            if (debugDetail != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Technical details'),
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      debugDetail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Browser URL for a known, user-owned Supabase project.
///
/// The project ref is already validated before a profile can become READY; the
/// repeat check keeps this UI boundary fail-closed and ensures no capability,
/// management token, or runtime key can reach an external URL.
Uri supabaseProjectDashboardUrl(String projectRef) {
  if (!RegExp(r'^[a-z]{20}$').hasMatch(projectRef)) {
    throw ArgumentError.value(
      projectRef,
      'projectRef',
      'must be a project ref',
    );
  }
  return Uri.https('supabase.com', '/dashboard/project/$projectRef');
}
