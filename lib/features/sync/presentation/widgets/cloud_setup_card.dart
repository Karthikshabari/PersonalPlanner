import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/error_panel.dart';
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

class _CloudSetupCardState extends ConsumerState<CloudSetupCard> {
  ProvisioningUiController? _controller;

  @override
  void initState() {
    super.initState();
    // Loading and resume happen when the user actually opens this screen; there
    // is no provisioning work at application startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(provisioningUiProvider.notifier);
      _controller = controller;
      unawaited(controller.startWatching());
    });
  }

  @override
  void dispose() {
    // Presentation polling must never outlive the screen.
    _controller?.stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        return _CloudCard(
          icon: Icons.cloud_done_outlined,
          title: 'Cloud backend ready',
          body: profile == null
              ? cloudSetupReadyBody
              : '$cloudSetupReadyBody\n\nSupabase project: ${profile.projectRef}',
          debugDetail: debugDetail,
          busy: busy,
        );
    }
  }

  String _stageLabel(CloudSetupStage? stage) => switch (stage) {
    CloudSetupStage.creatingProject => 'Creating cloud project',
    CloudSetupStage.preparingDatabase => 'Preparing database',
    CloudSetupStage.verifyingSetup => 'Verifying setup',
    null => 'Setting up your cloud backend',
  };

  /// Debug-only, non-secret identifiers: never credentials or keys.
  String? _debugDetail(ProvisioningUiState state) {
    if (!kDebugMode) return null;
    final parts = <String>[
      if (state.transactionId != null) 'transaction ${state.transactionId}',
      if (state.errorCode != null) 'code ${state.errorCode}',
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
              Text(
                debugDetail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
