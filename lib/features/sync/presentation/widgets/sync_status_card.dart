import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/sync_models.dart';
import 'sync_action_group.dart';

/// Compact presentation of the current synchronization state.
///
/// The panel is deliberately still: it animates only while a real sync cycle is
/// running. An enabled-but-idle account shows a plain status line, never a
/// spinner, and the last-sync timestamp is humanised instead of printed as a
/// raw instant.
class SyncStatusPanel extends StatelessWidget {
  const SyncStatusPanel({
    super.key,
    required this.status,
    required this.enabled,
    required this.busy,
    required this.onSyncNow,
    this.now,
  });

  final SyncStatusSnapshot status;
  final bool enabled;
  final bool busy;
  final VoidCallback onSyncNow;

  /// Injectable clock so tests can assert the humanised timestamp.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final view = syncStatusView(
      status,
      enabled: enabled,
      tokens: tokens,
      now: now,
    );
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
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// True only while a real synchronization cycle is running.
  final bool active;

  /// Label of the manual action for this state.
  final String actionLabel;
}

SyncStatusView syncStatusView(
  SyncStatusSnapshot status, {
  required bool enabled,
  required AppThemeTokens tokens,
  DateTime? now,
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
  final lastLine = lastSynced == null
      ? 'Not synced yet'
      : 'Last synced ${_relativeTimestamp(lastSynced, now: now)}';
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
        subtitle: status.message ?? lastLine,
      );
    case SyncEngineState.offline:
      return SyncStatusView(
        icon: Icons.cloud_off,
        color: tokens.offline,
        title: 'Cloud sync paused',
        subtitle:
            "You're offline. Changes will sync when you're connected again.",
      );
    case SyncEngineState.backendUnavailable:
      return SyncStatusView(
        icon: Icons.cloud_off_outlined,
        color: tokens.error,
        title: 'Cloud unavailable',
        subtitle:
            status.message ??
            'Your cloud storage could not be reached. Your local data is '
                'safe.',
        actionLabel: 'Try again',
      );
    case SyncEngineState.authFailure:
      return SyncStatusView(
        icon: Icons.lock_outline,
        color: tokens.error,
        title: 'Sign in required',
        subtitle: status.message ?? 'Log in again to continue syncing.',
      );
    case SyncEngineState.conflict:
      return SyncStatusView(
        icon: Icons.warning_amber,
        color: tokens.pending,
        title: 'Conflicts need a decision',
        subtitle:
            status.message ??
            'Choose which copy to keep for the records listed below.',
      );
    case SyncEngineState.permanentFailure:
      return SyncStatusView(
        icon: Icons.report_problem_outlined,
        color: tokens.error,
        title: 'Sync needs a repair',
        subtitle:
            status.message ??
            'A change could not be uploaded and is listed below.',
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
      );
    case SyncEngineState.partialSuccess:
    case SyncEngineState.invalidData:
    case SyncEngineState.error:
      return SyncStatusView(
        icon: Icons.error_outline,
        color: tokens.error,
        title: "Sync couldn't complete",
        subtitle: status.message ?? 'Your changes are safe on this device.',
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

/// Human-friendly form of a sync instant: "Just now", "5 minutes ago",
/// "Today at 9:47 PM", "Yesterday at 9:47 PM".
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

/// Lower-cased form used inside a sentence ("Last synced 5 minutes ago").
String _relativeTimestamp(DateTime value, {DateTime? now}) {
  final formatted = formatSyncTimestamp(value, now: now);
  return formatted.isEmpty
      ? formatted
      : formatted[0].toLowerCase() + formatted.substring(1);
}

String _clockTime(DateTime local) {
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = _twoDigits(local.minute);
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
