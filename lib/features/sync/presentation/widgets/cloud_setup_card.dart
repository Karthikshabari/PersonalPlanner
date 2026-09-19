import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/runtime_backend_providers.dart';
import '../../providers/provisioning_providers.dart';
import '../controllers/provisioning_ui_controller.dart';
import 'cloud_setup_preflight.dart';
import 'sync_action_group.dart';

/// Settings → Sync card for the user-owned Supabase setup flow.
///
/// Presentation only: it drives [ProvisioningUiController] and never talks to
/// the Worker, secure storage or the Durable Object directly.
class CloudSetupCard extends ConsumerStatefulWidget {
  const CloudSetupCard({
    super.key,
    this.onUseOfflineOnly,
    this.onStopUsingCloud,
  });

  /// Lets the user stop using the (now missing) cloud backend from the
  /// recovery card. The Settings screen owns that lifecycle action, so it is
  /// injected rather than duplicated here.
  final Future<void> Function()? onUseOfflineOnly;

  /// Lets the user stop using a healthy cloud backend on this device from the
  /// Advanced section. Same injected lifecycle action as [onUseOfflineOnly];
  /// nothing about the underlying behaviour changes here.
  final Future<void> Function()? onStopUsingCloud;

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
    // A Management authorization that is still outstanding is also resolved by
    // coming back to the app, even when the automatic deep link did not fire.
    if (controller.current?.managementCheckInFlight ?? false) {
      unawaited(controller.completeManagementCheck());
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
        title: const Text('Cancel Supabase access?'),
        content: const Text(
          'This cancels the temporary Supabase authorization Personal Planner '
          'is currently holding.\n\n'
          '• Your Supabase project and its data are not deleted.\n'
          '• Your Planner account and sign-in are not affected.\n'
          '• Local Planner data stays on this device.\n'
          '• You can connect to Supabase again later from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('cloud-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(cloudSetupCancelAccessLabel),
          ),
        ],
      ),
    );
    if (choice != true) return;
    await controller.disconnectSupabaseAccess();
  }

  /// Confirms the first project creation, then runs exactly the existing
  /// provisioning entry point. Cancel (or dismissing the dialog) starts
  /// nothing.
  Future<void> _startSetupWithPreflight(
    ProvisioningUiController controller,
  ) async {
    final confirmed = await showCloudSetupPreflight(context);
    if (!confirmed || !mounted) return;
    await controller.startSetup();
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

    switch (state.phase) {
      case ProvisioningUiPhase.unavailable:
        return _CloudCard(
          icon: Icons.cloud_off,
          title: cloudStorageTitle,
          body: state.message ?? cloudSetupUnavailableMessage,
        );

      case ProvisioningUiPhase.localOnly:
        return _CloudCard(
          icon: Icons.cloud_outlined,
          title: cloudStorageTitle,
          body: cloudSetupLocalOnlyBody,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-enable-action'),
              onPressed: busy
                  ? null
                  : () => unawaited(_startSetupWithPreflight(controller)),
              child: const Text('Set up cloud storage'),
            ),
          ],
        );

      case ProvisioningUiPhase.waitingForAuthorization:
        return _CloudCard(
          icon: Icons.verified_user_outlined,
          title: cloudStorageTitle,
          status: cloudStorageWaitingStatus,
          statusTone: _StatusTone.pending,
          body: state.message ?? cloudSetupWaitingMessage,
          busy: busy,
          progress: true,
          actions: <Widget>[
            OutlinedButton(
              key: const ValueKey('cloud-check-authorization'),
              onPressed: busy ? null : controller.checkAuthorization,
              child: const Text('Refresh status'),
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
          busy: busy,
          confirmation: state.authorizationConfirmed
              ? cloudSetupAuthorizationConfirmedMessage
              : null,
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
          title: cloudStorageTitle,
          status: _stageLabel(state.stage),
          statusTone: _StatusTone.pending,
          confirmation: state.authorizationConfirmed
              ? cloudSetupAuthorizationConfirmedMessage
              : null,
          body: cloudSetupLeaveHint,
          busy: busy,
          progress: true,
          actions: <Widget>[
            TextButton(
              key: const ValueKey('cloud-check-progress'),
              onPressed: busy ? null : controller.advance,
              child: const Text('Refresh status'),
            ),
          ],
        );

      case ProvisioningUiPhase.retryableError:
        return _CloudCard(
          icon: Icons.cloud_off,
          title: 'Cloud setup paused',
          body: state.message ?? cloudSetupRetryableMessage,
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
        final unreachable =
            state.reachability == CloudReachability.unavailable;
        return _CloudCard(
          key: const ValueKey('cloud-storage-ready'),
          icon: Icons.cloud_done_outlined,
          title: cloudStorageTitle,
          status: unreachable
              ? cloudStorageUnreachableStatus
              : cloudStorageConnectedStatus,
          statusTone: unreachable ? _StatusTone.warning : _StatusTone.success,
          // A lifecycle action on this card (check connection, revoke
          // temporary access) reports its result here, so the ready body gives
          // way to the explicit outcome message.
          body: state.message ?? cloudSetupReadyBody,
          busy: busy,
          actions: <Widget>[
            if (unreachable)
              FilledButton(
                key: const ValueKey('cloud-retry-probe-action'),
                onPressed: busy ? null : controller.verifyProjectHost,
                child: const Text('Try again'),
              ),
            if (unreachable)
              OutlinedButton(
                key: const ValueKey('cloud-reauthorize-action'),
                onPressed: busy || state.managementCheckInFlight
                    ? null
                    : controller.reauthorizeSupabaseAccess,
                child: Text(
                  state.managementCheckInFlight
                      ? 'Waiting for Supabase…'
                      : cloudSetupCheckConnectionLabel,
                ),
              ),
            if (!unreachable && projectRef != null)
              OutlinedButton(
                key: const ValueKey('cloud-open-dashboard'),
                onPressed: busy
                    ? null
                    : () => unawaited(_openProjectDashboard(projectRef)),
                child: const Text('Open Supabase'),
              ),
          ],
          content: _SupabaseAccessSection(
            state: state,
            controller: controller,
            busy: busy,
            onStopUsingCloud: widget.onStopUsingCloud,
            onRequestRevoke: () =>
                unawaited(_confirmSupabaseAccessDisconnect(controller)),
          ),
        );

      case ProvisioningUiPhase.remoteMissing:
        return _CloudCard(
          key: const ValueKey('cloud-remote-missing'),
          icon: Icons.cloud_off_outlined,
          title: cloudStorageTitle,
          status: cloudRemoteMissingTitle,
          statusTone: _StatusTone.error,
          body: cloudRemoteMissingBody,
          busy: busy,
          actions: <Widget>[
            FilledButton(
              key: const ValueKey('cloud-setup-again-action'),
              onPressed: busy
                  ? null
                  : () => unawaited(_startSetupWithPreflight(controller)),
              child: const Text('Set up cloud storage again'),
            ),
            OutlinedButton(
              key: const ValueKey('cloud-use-offline-only-action'),
              onPressed: busy ? null : widget.onUseOfflineOnly,
              child: const Text('Use offline-only mode'),
            ),
          ],
        );

      case ProvisioningUiPhase.disconnected:
        final profile = state.readyProfile;
        final projectRef = profile?.projectRef;
        return _CloudCard(
          icon: Icons.cloud_off_outlined,
          title: cloudStorageTitle,
          status: cloudStorageDisconnectedStatus,
          statusTone: _StatusTone.neutral,
          body: state.message ?? cloudSetupDisconnectedBody,
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
                child: const Text('Open Supabase'),
              ),
          ],
        );
    }
  }

  String _stageLabel(CloudSetupStage? stage) => switch (stage) {
    CloudSetupStage.preparingProject => 'Creating your cloud project…',
    CloudSetupStage.waitingForProject =>
      'Waiting for your cloud project to be ready…',
    CloudSetupStage.installingPlannerSchema => 'Configuring your database…',
    CloudSetupStage.verifyingCloudStorage => 'Finishing setup…',
    null => 'Setting up cloud storage…',
  };

}

/// Secondary "Supabase connection" area of a healthy cloud connection.
///
/// It collapses by default so the ordinary screen only shows the state, what it
/// means and the one useful action. Least privilege is unchanged, and the
/// wording no longer needs to explain it: the normal case simply offers a check
/// instead of a disconnect that would have nothing to revoke.
class _SupabaseAccessSection extends StatelessWidget {
  const _SupabaseAccessSection({
    required this.state,
    required this.controller,
    required this.busy,
    required this.onStopUsingCloud,
    required this.onRequestRevoke,
  });

  final ProvisioningUiState state;
  final ProvisioningUiController controller;
  final bool busy;
  final Future<void> Function()? onStopUsingCloud;
  final VoidCallback onRequestRevoke;

  @override
  Widget build(BuildContext context) {
    final inFlight = state.managementCheckInFlight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1),
        Theme(
          // An expansion tile is used as a plain disclosure control; the
          // surrounding card already supplies the visual boundary.
          data: Theme.of(
            context,
          ).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('cloud-advanced-access'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
            leading: const Icon(Icons.link_outlined),
            title: const Text(cloudSetupSupabaseAccessTitle),
            subtitle: const Text(cloudSetupSupabaseAccessBody),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (inFlight) ...[
                      Text(
                        cloudSetupSupabaseAccessPending,
                        key: const ValueKey('cloud-management-status'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    SyncActionGroup(
                      alignment: WrapAlignment.start,
                      actions: <Widget>[
                        if (inFlight)
                          FilledButton(
                            key: const ValueKey('cloud-revoke-action'),
                            onPressed: busy ? null : onRequestRevoke,
                            child: const Text(cloudSetupCancelAccessLabel),
                          )
                        else
                          OutlinedButton(
                            key: const ValueKey('cloud-reauthorize-action'),
                            onPressed: busy
                                ? null
                                : controller.reauthorizeSupabaseAccess,
                            child: const Text(
                              cloudSetupCheckConnectionLabel,
                            ),
                          ),
                      ],
                    ),
                    // The device-level lifecycle action is deliberately
                    // separated from the ordinary check above: it changes how
                    // this device uses the cloud, and keeps its confirmation.
                    if (onStopUsingCloud != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1),
                      ListTile(
                        key: const ValueKey('cloud-stop-using-cloud-action'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_off_outlined),
                        title: const Text(cloudSetupStopUsingCloudLabel),
                        subtitle: const Text(cloudSetupStopUsingCloudSupport),
                        onTap: busy
                            ? null
                            : () => unawaited(onStopUsingCloud!()),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _StatusTone { neutral, pending, success, warning, error }

class _CloudCard extends StatelessWidget {
  const _CloudCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.content,
    this.actions = const <Widget>[],
    this.busy = false,
    this.status,
    this.statusTone = _StatusTone.neutral,
    this.progress = false,
    this.confirmation,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? content;
  final List<Widget> actions;
  final bool busy;
  final String? status;
  final _StatusTone statusTone;

  /// True while this phase genuinely waits on server-side work.
  final bool progress;

  /// Optional inline acknowledgement of a step that just completed.
  final String? confirmation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CloudCardHeading(
                      title: title,
                      status: status,
                      tone: statusTone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (confirmation != null) ...[
                _InlineConfirmation(message: confirmation!),
                const SizedBox(height: 8),
              ],
              Text(body),
              ?content,
              // Exactly one indeterminate indicator per card: either the
              // phase's own waiting progress or the feedback for a user
              // action. Two identical bars carried no extra meaning.
              if (progress || busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                SyncActionGroup(actions: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineConfirmation extends StatelessWidget {
  const _InlineConfirmation({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, size: 16, color: tokens.success),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.success),
          ),
        ),
      ],
    );
  }
}

class _CloudCardHeading extends StatelessWidget {
  const _CloudCardHeading({
    required this.title,
    required this.status,
    required this.tone,
  });

  final String title;
  final String? status;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final statusColor = switch (tone) {
      _StatusTone.success => tokens.success,
      _StatusTone.pending => tokens.pending,
      _StatusTone.warning => tokens.warning,
      _StatusTone.error => tokens.error,
      _StatusTone.neutral => tokens.textSecondary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (status != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (tone) {
                  _StatusTone.success => Icons.check_circle,
                  _StatusTone.pending => Icons.sync,
                  _StatusTone.warning => Icons.error_outline,
                  _StatusTone.error => Icons.report_problem_outlined,
                  _StatusTone.neutral => Icons.circle_outlined,
                },
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  status!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
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
