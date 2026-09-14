import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/sync_models.dart';
import '../../providers/sync_providers.dart';

/// Compact status entry point for primary screens. Details and manual sync
/// remain in Sync Settings; this widget never reads remote data directly.
class SyncStatusAction extends ConsumerWidget {
  const SyncStatusAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final statusAsync = ref.watch(syncStatusProvider);
    final status = statusAsync.value;
    final state = statusAsync.hasError
        ? SyncEngineState.error
        : status?.state ?? SyncEngineState.notConfigured;
    return IconButton(
      key: const ValueKey('sync-status-action'),
      tooltip: statusAsync.hasError
          ? 'Sync status unavailable. Open Sync settings to retry.'
          : _tooltip(status),
      color: _color(tokens, state),
      icon: Icon(_icon(state)),
      onPressed: () => context.push('/settings/sync'),
    );
  }

  static String _tooltip(SyncStatusSnapshot? status) {
    final snapshot = status;
    if (snapshot == null) return 'Sync status';
    if (snapshot.pendingOperations > 0) {
      return '${snapshot.state.label}: ${snapshot.pendingOperations} pending';
    }
    if (snapshot.conflictCount > 0) {
      return '${snapshot.state.label}: ${snapshot.conflictCount} conflict(s)';
    }
    return snapshot.state.label;
  }

  static IconData _icon(SyncEngineState state) => switch (state) {
    SyncEngineState.synced => Icons.cloud_done,
    SyncEngineState.syncing => Icons.sync,
    SyncEngineState.pending => Icons.cloud_upload,
    SyncEngineState.offline => Icons.cloud_off,
    SyncEngineState.refreshPaused => Icons.refresh,
    SyncEngineState.error ||
    SyncEngineState.conflict ||
    SyncEngineState.partialSuccess ||
    SyncEngineState.permanentFailure ||
    SyncEngineState.authFailure ||
    SyncEngineState.invalidData => Icons.warning_amber,
    SyncEngineState.notConfigured => Icons.cloud_queue,
  };

  static Color? _color(AppThemeTokens tokens, SyncEngineState state) =>
      switch (state) {
        SyncEngineState.synced => tokens.success,
        SyncEngineState.syncing => tokens.info,
        SyncEngineState.pending => tokens.pending,
        SyncEngineState.offline ||
        SyncEngineState.notConfigured => tokens.offline,
        SyncEngineState.refreshPaused => tokens.pending,
        SyncEngineState.error ||
        SyncEngineState.conflict ||
        SyncEngineState.partialSuccess ||
        SyncEngineState.permanentFailure ||
        SyncEngineState.authFailure ||
        SyncEngineState.invalidData => tokens.error,
      };
}
