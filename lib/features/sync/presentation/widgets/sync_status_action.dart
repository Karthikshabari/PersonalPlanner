import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/sync_models.dart';
import '../../providers/sync_providers.dart';
import 'sync_status_card.dart' show formatSyncClockTime;

/// Compact status entry point for primary screens. Details and manual sync
/// remain in Sync Settings; this widget never reads remote data directly.
class SyncStatusAction extends ConsumerStatefulWidget {
  const SyncStatusAction({super.key});

  static const _syncRoute = '/settings/sync';

  @override
  ConsumerState<SyncStatusAction> createState() => _SyncStatusActionState();
}

class _SyncStatusActionState extends ConsumerState<SyncStatusAction>
    with TickerProviderStateMixin {
  /// Exists only while the engine is syncing (and motion is allowed), so no
  /// ticker runs in any other state.
  AnimationController? _spin;

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  void _setSpinning(bool spinning) {
    if (spinning && _spin == null) {
      _spin = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      )..repeat();
    } else if (!spinning && _spin != null) {
      _spin!.dispose();
      _spin = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final statusAsync = ref.watch(syncStatusProvider);
    final status = statusAsync.value;
    final state = statusAsync.hasError
        ? SyncEngineState.error
        : status?.state ?? SyncEngineState.notConfigured;
    _setSpinning(
      state == SyncEngineState.syncing &&
          !MediaQuery.disableAnimationsOf(context),
    );
    final label = statusAsync.hasError
        ? 'Sync status unavailable. Open Sync settings to retry.'
        : _label(status);
    final color = _color(tokens, state);
    Widget icon = Icon(_icon(state), color: color);
    final spin = _spin;
    if (spin != null) {
      icon = RotationTransition(turns: spin, child: icon);
    } else if (_showsErrorDot(state)) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          PositionedDirectional(
            top: 0,
            end: 0,
            child: SizedBox.square(
              dimension: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.canvas, width: 1),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // One spoken description on the button's own node: the label sits on the
    // icon (merged into the IconButton's node), and the tooltip is visual only
    // so it is not read twice. A wrapping Semantics would put the label on a
    // parent of the button node, and excludeSemantics would drop its tap.
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconButton(
        key: const ValueKey('sync-status-action'),
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        icon: Semantics(label: label, child: icon),
        onPressed: () {
          // Already on Sync settings: another push would stack a duplicate
          // page (UAT F-014).
          final router = GoRouter.of(context);
          if (router.state.uri.path == SyncStatusAction._syncRoute) return;
          router.push(SyncStatusAction._syncRoute);
        },
      ),
    );
  }

  /// "Sync: Pending · 3 pending · 1 conflict · Last synced 14:05".
  static String _label(SyncStatusSnapshot? status) {
    if (status == null) return 'Sync status';
    if (status.state == SyncEngineState.notConfigured) {
      return 'Local only. Set up cloud sync';
    }
    final parts = [
      'Sync: ${status.state.label}',
      if (status.pendingOperations > 0) '${status.pendingOperations} pending',
      if (status.conflictCount > 0) '${status.conflictCount} conflict(s)',
      if (status.lastSuccessfulSync case final last?)
        'Last synced ${formatSyncClockTime(last)}',
    ];
    return parts.join(' · ');
  }

  static bool _showsErrorDot(SyncEngineState state) => switch (state) {
    SyncEngineState.error ||
    SyncEngineState.conflict ||
    SyncEngineState.partialSuccess ||
    SyncEngineState.permanentFailure ||
    SyncEngineState.authFailure ||
    SyncEngineState.invalidData => true,
    SyncEngineState.synced ||
    SyncEngineState.syncing ||
    SyncEngineState.pending ||
    SyncEngineState.initialSyncPending ||
    SyncEngineState.refreshPaused ||
    SyncEngineState.offline ||
    SyncEngineState.backendUnavailable ||
    SyncEngineState.notConfigured => false,
  };

  static IconData _icon(SyncEngineState state) => switch (state) {
    SyncEngineState.synced => Icons.cloud_done_outlined,
    SyncEngineState.syncing ||
    SyncEngineState.pending ||
    SyncEngineState.initialSyncPending ||
    SyncEngineState.refreshPaused => Icons.sync,
    SyncEngineState.offline ||
    SyncEngineState.backendUnavailable => Icons.cloud_off_outlined,
    SyncEngineState.error ||
    SyncEngineState.conflict ||
    SyncEngineState.partialSuccess ||
    SyncEngineState.permanentFailure ||
    SyncEngineState.authFailure ||
    SyncEngineState.invalidData => Icons.cloud_off,
    SyncEngineState.notConfigured => Icons.cloud_queue_outlined,
  };

  static Color _color(AppThemeTokens tokens, SyncEngineState state) =>
      switch (state) {
        SyncEngineState.synced => tokens.success,
        SyncEngineState.syncing ||
        SyncEngineState.pending ||
        SyncEngineState.initialSyncPending ||
        SyncEngineState.refreshPaused => tokens.info,
        SyncEngineState.offline ||
        SyncEngineState.backendUnavailable => tokens.offline,
        SyncEngineState.error ||
        SyncEngineState.conflict ||
        SyncEngineState.partialSuccess ||
        SyncEngineState.permanentFailure ||
        SyncEngineState.authFailure ||
        SyncEngineState.invalidData => tokens.error,
        SyncEngineState.notConfigured => tokens.textMuted,
      };
}
