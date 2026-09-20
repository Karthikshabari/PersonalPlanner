import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/sync_models.dart';
import 'sync_action_group.dart';

/// Compact presentation of the current synchronization state.
///
/// The panel is deliberately still: it animates only while a real sync cycle is
/// running. An enabled-but-idle account shows a plain status line, never a
/// spinner, and the last-sync timestamp is a stable wall-clock instant. The
/// panel never owns a clock, so it can redraw for any reason without the
/// last-sync text changing under the user.
class SyncStatusPanel extends StatelessWidget {
  const SyncStatusPanel({
    super.key,
    required this.status,
    required this.enabled,
    required this.busy,
    required this.onSyncNow,
  });

  final SyncStatusSnapshot status;
  final bool enabled;
  final bool busy;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final view = syncStatusView(status, enabled: enabled, tokens: tokens);
    final action = FilledButton(
      key: const ValueKey('sync-now-action'),
      onPressed: enabled && !busy ? onSyncNow : null,
      child: Text(view.actionLabel),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          view.title,
          key: const ValueKey('sync-status-title'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs / 2),
        Text(view.subtitle),
        if (view.lastSyncLine != null) ...[
          const SizedBox(height: AppSpacing.xs / 2),
          Text(
            view.lastSyncLine!,
            key: const ValueKey('sync-last-sync-line'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (status.pendingOperations > 0 && enabled) ...[
          const SizedBox(height: AppSpacing.xs / 2),
          Text(
            view.active
                ? _remainingLabel(status.pendingOperations)
                : _pendingLabel(status.pendingOperations),
            key: const ValueKey('sync-pending-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );

    return Card(
      key: const ValueKey('sync-status-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusGlyph(view: view),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SyncActionGroup(actions: <Widget>[action]),
          ],
        ),
      ),
    );
  }

  static String _pendingLabel(int count) => count == 1
      ? '1 change is waiting to sync.'
      : '$count changes are waiting to sync.';

  static String _remainingLabel(int count) => count == 1
      ? '1 change remaining.'
      : '$count changes remaining.';
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.view});

  final SyncStatusView view;

  @override
  Widget build(BuildContext context) {
    if (view.active) {
      return Semantics(
        label: 'Sync in progress',
        child: const SizedBox(
          key: ValueKey('sync-active-indicator'),
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Icon(
      view.icon,
      key: const ValueKey('sync-status-icon'),
      color: view.color,
    );
  }
}

/// Everything the panel needs to render one state, so the mapping can be unit
/// tested without a widget tree.
@immutable
class SyncStatusView {
  const SyncStatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.active = false,
    this.actionLabel = 'Sync now',
    this.lastSyncLine,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// True only while a real synchronization cycle is running.
  final bool active;

  /// Label of the manual action for this state.
  final String actionLabel;

  /// Stable statement of the last successful synchronization, rendered as its
  /// own line when the subtitle already says something else.
  final String? lastSyncLine;
}

SyncStatusView syncStatusView(
  SyncStatusSnapshot status, {
  required bool enabled,
  required AppThemeTokens tokens,
}) {
  if (!enabled) {
    return SyncStatusView(
      icon: Icons.cloud_off_outlined,
      color: tokens.offline,
      title: 'Sync is off',
      subtitle:
          'Changes will stay on this device until you turn sync back on.',
    );
  }
  final lastSynced = status.lastSuccessfulSync;
  // Wall-clock wording only: it never ages by itself, so a rebuild can never
  // change it. Nothing here may run on a timer.
  final lastLine = lastSynced == null
      ? 'Not synced yet'
      : 'Last synced at ${formatSyncClockTime(lastSynced)}';
  final lastSuccessfulLine = lastSynced == null
      ? 'Not synced yet'
      : 'Last successful sync at ${formatSyncClockTime(lastSynced)}';
  const willSyncLine =
      'Changes will sync when the cloud connection is available.';
  switch (status.state) {
    case SyncEngineState.syncing:
      return SyncStatusView(
        icon: Icons.sync,
        color: tokens.info,
        title: 'Syncing…',
        subtitle:
            status.message ??
            'Uploading and downloading your latest changes.',
        active: true,
      );
    case SyncEngineState.synced:
      if (lastSynced == null) {
        // A reachable account that has never completed a real synchronization
        // must not claim to be up to date.
        return SyncStatusView(
          icon: Icons.cloud_queue,
          color: tokens.offline,
          title: 'Not synced yet',
          subtitle: 'No successful synchronization has completed yet.',
        );
      }
      return SyncStatusView(
        icon: Icons.check_circle,
        color: tokens.success,
        title: 'Up to date',
        subtitle: lastLine,
      );
    case SyncEngineState.pending:
      return SyncStatusView(
        icon: Icons.cloud_upload_outlined,
        color: tokens.pending,
        title: 'Waiting to sync',
        subtitle: status.message ?? willSyncLine,
        lastSyncLine: lastLine,
      );
    case SyncEngineState.offline:
      return SyncStatusView(
        icon: Icons.cloud_off,
        color: tokens.offline,
        title: 'Cloud sync paused',
        subtitle:
            "You're offline. Changes will sync when you're connected again.",
        lastSyncLine: lastLine,
      );
    case SyncEngineState.backendUnavailable:
      return SyncStatusView(
        icon: Icons.cloud_off_outlined,
        color: tokens.error,
        title: "Couldn't reach cloud storage",
        subtitle: status.message ?? willSyncLine,
        lastSyncLine: lastSuccessfulLine,
        actionLabel: 'Try again',
      );
    case SyncEngineState.authFailure:
      return SyncStatusView(
        icon: Icons.lock_outline,
        color: tokens.error,
        title: 'Reauthorization required',
        subtitle:
            status.message ??
            'Sign in again to resume syncing. Local data stays on this device.',
        lastSyncLine: lastSuccessfulLine,
      );
    case SyncEngineState.conflict:
      return SyncStatusView(
        icon: Icons.warning_amber,
        color: tokens.pending,
        title: 'Conflicts need a decision',
        subtitle:
            status.message ??
            'Choose which copy to keep for the records listed below.',
        lastSyncLine: lastSuccessfulLine,
      );
    case SyncEngineState.permanentFailure:
      return SyncStatusView(
        icon: Icons.report_problem_outlined,
        color: tokens.error,
        title: 'Sync needs a repair',
        subtitle:
            status.message ??
            'A change could not be uploaded and is listed below.',
        lastSyncLine: lastSuccessfulLine,
      );
    case SyncEngineState.initialSyncPending:
      return SyncStatusView(
        icon: Icons.cloud_sync_outlined,
        color: tokens.pending,
        title: 'Setting up sync',
        subtitle:
            status.message ?? 'Your first synchronization is still in progress.',
      );
    case SyncEngineState.refreshPaused:
      return SyncStatusView(
        icon: Icons.refresh,
        color: tokens.pending,
        title: 'Sync paused',
        subtitle:
            status.message ?? 'Sync resumes after the session is refreshed.',
        lastSyncLine: lastSuccessfulLine,
      );
    case SyncEngineState.partialSuccess:
    case SyncEngineState.invalidData:
    case SyncEngineState.error:
      return SyncStatusView(
        icon: Icons.error_outline,
        color: tokens.error,
        title: "Couldn't sync",
        subtitle:
            status.message ??
            'Your changes are safe on this device and will be retried.',
        lastSyncLine: lastSuccessfulLine,
        actionLabel: 'Try again',
      );
    case SyncEngineState.notConfigured:
      return SyncStatusView(
        icon: Icons.cloud_queue,
        color: tokens.offline,
        title: 'Sync is not set up',
        subtitle:
            status.message ??
            'Cloud synchronization is not configured for this account yet.',
      );
  }
}

/// Stable clock form used by the Sync screen: "11:51 PM".
///
/// This is deliberately not relative: the Sync screen must not re-render
/// "just now"/"N minutes ago" as a clock ticks.
String formatSyncClockTime(DateTime value) => _clockTime(value.toLocal());

/// Human-friendly form of a sync instant: "Just now", "5 minutes ago",
/// "Today at 9:47 PM", "Yesterday at 9:47 PM".
///
/// Retained for non-sync surfaces that genuinely want a relative phrase. The
/// Sync panel itself uses [formatSyncClockTime] so its text is stable.
String formatSyncTimestamp(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final difference = reference.difference(local);
  if (difference.isNegative || difference.inSeconds < 45) return 'Just now';
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
  }
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  final clock = _clockTime(local);
  if (days == 0) return 'Today at $clock';
  if (days == 1) return 'Yesterday at $clock';
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      'at $clock';
}

String _clockTime(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = _twoDigits(local.minute);
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
