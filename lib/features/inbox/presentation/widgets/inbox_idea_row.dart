import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/inbox_closure.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/clock_format.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../review/presentation/widgets/review_animated_size.dart';
import '../../../timeline/presentation/providers/day_view_controller.dart';
import '../../domain/inbox_board.dart';
import '../../domain/inbox_session_text.dart';
import '../../domain/inbox_status.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_badge.dart';
import 'inbox_quick_add.dart';
import 'inbox_trail.dart';

/// One idea in the Inbox list. It watches only its own [InboxIdeaView] (through
/// `select`), so a change to another idea does not rebuild it. Tapping, Enter
/// or Space opens the trail; only one row is open at a time.
class InboxIdeaRow extends ConsumerStatefulWidget {
  const InboxIdeaRow({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<InboxIdeaRow> createState() => _InboxIdeaRowState();
}

class _InboxIdeaRowState extends ConsumerState<InboxIdeaRow> {
  final _headerFocus = FocusNode(debugLabel: 'inbox-row-header');

  @override
  void dispose() {
    _headerFocus.dispose();
    super.dispose();
  }

  void _toggle(bool expanded) {
    ref.read(inboxExpandedItemProvider.notifier).state = expanded
        ? null
        : widget.itemId;
  }

  void _collapse() {
    if (ref.read(inboxExpandedItemProvider) != widget.itemId) return;
    ref.read(inboxExpandedItemProvider.notifier).state = null;
    _headerFocus.requestFocus();
  }

  Future<void> _delete() async {
    final task = await ref
        .read(taskRepositoryProvider)
        .getTaskById(widget.itemId);
    if (task == null || !mounted) return;
    final view = ref.read(inboxBoardProvider).value?.byId[widget.itemId];
    await TimelineActions.deleteWithConfirmation(
      context,
      ref,
      task,
      pastSessions: view == null ? 0 : _pastSessions(view),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      inboxBoardProvider.select((board) => board.value?.byId[widget.itemId]),
    );
    if (view == null) return const SizedBox.shrink();
    final expanded = ref.watch(
      inboxExpandedItemProvider.select((id) => id == widget.itemId),
    );
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final title = _title(view);
    final line = _statusLine(view);
    final badge = _badge(context, view);
    final (icon, tint) = _icon(tokens, view);
    final canDelete = inboxIdeaCanDelete(view);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _collapse},
      child: AppSurface(
        key: ValueKey('inbox-item-${view.item.id}'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    expanded: expanded,
                    label: badge == null
                        ? '$title. $line'
                        : '$title. $line. ${badge.label}',
                    excludeSemantics: true,
                    onTap: () => _toggle(expanded),
                    child: InkWell(
                      key: ValueKey('inbox-row-header-${view.item.id}'),
                      focusNode: _headerFocus,
                      borderRadius: BorderRadius.circular(tokens.radiusSmall),
                      onTap: () => _toggle(expanded),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: tint.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusSmall,
                                  ),
                                ),
                                child: Icon(icon, size: 17, color: tint),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Tooltip(
                                      message: title,
                                      excludeFromSemantics: true,
                                      child: PageSearchHighlight(
                                        title,
                                        maxLines: 2,
                                        style: textTheme.labelLarge,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.xs,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          line,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: tokens.textMuted,
                                          ),
                                        ),
                                        ?badge,
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('inbox-menu-${view.item.id}'),
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More actions',
                  onSelected: (value) {
                    if (value == 'edit') {
                      showInboxEditDialog(
                        context,
                        ref,
                        taskId: view.item.id,
                        initialContent: view.item.text,
                      );
                    }
                    if (value == 'delete') _delete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: canDelete,
                      child: Text(
                        canDelete ? 'Delete' : 'Delete (close it first)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ReviewAnimatedSize(
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.xs + 28 + AppSpacing.sm,
                        right: AppSpacing.xs,
                        top: AppSpacing.sm,
                        bottom: AppSpacing.xs,
                      ),
                      child: InboxTrail(view: view),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  String _title(InboxIdeaView view) {
    final title = inboxSessionText(view.item.text).title;
    return title.isEmpty ? 'Inbox capture' : title;
  }

  String _statusLine(InboxIdeaView view) {
    final captured =
        'Captured ${DateFormat('MMM d').format(PlannerTimeZone.toPlannerLocal(view.item.createdAt))}';
    switch (view.status) {
      case InboxItemStatus.left:
        final start = view.lastMissedStart;
        if (start == null) return captured;
        final local = PlannerTimeZone.toPlannerLocal(start);
        return '${DateFormat('EEE, MMM d').format(local)}'
            ' · ${formatClock24(local)}';
      case InboxItemStatus.soon:
        final start = view.nextStart;
        if (start == null) return captured;
        final local = PlannerTimeZone.toPlannerLocal(start);
        final count = view.upcomingCount;
        return 'Next ${DateFormat('EEE, MMM d').format(local)}'
            ' · ${formatClock24(local)}'
            ' · $count ${count == 1 ? 'session' : 'sessions'}';
      case InboxItemStatus.idea:
        final due = view.item.dueDate;
        if (due == null || !isValidIsoDate(due)) return captured;
        final today = isoDateString(ref.watch(inboxScreenClockProvider));
        final label = DateFormat('MMM d').format(parseIsoDate(due));
        return '$captured · ${due.compareTo(today) < 0 ? 'Was due' : 'Due'} $label';
      case InboxItemStatus.finished:
      case InboxItemStatus.closed:
        return captured;
    }
  }

  InboxBadge? _badge(BuildContext context, InboxIdeaView view) {
    final tokens = AppThemeTokens.of(context);
    return switch (view.status) {
      InboxItemStatus.left => InboxBadge(
        label: 'Missed',
        color: tokens.warning,
      ),
      InboxItemStatus.finished || InboxItemStatus.closed =>
        view.chip == null ? null : InboxBadge.outcome(context, view.chip!),
      InboxItemStatus.idea || InboxItemStatus.soon => null,
    };
  }

  (IconData, Color) _icon(AppThemeTokens tokens, InboxIdeaView view) =>
      switch (view.status) {
        InboxItemStatus.left => (Icons.history, tokens.warning),
        InboxItemStatus.idea => (Icons.inbox_outlined, tokens.info),
        InboxItemStatus.soon => (Icons.event, tokens.info),
        InboxItemStatus.finished => (
          Icons.check_circle_outline,
          tokens.success,
        ),
        InboxItemStatus.closed =>
          view.closure?.kind == InboxCloseKind.experiment
              ? (Icons.check_circle_outline, tokens.textMuted)
              : (Icons.remove_circle_outline, tokens.textMuted),
      };
}

/// An idea can be deleted unless a session is still upcoming or in progress
/// (both are `upcoming`). Done, missed, skipped, carried and dropped sessions
/// do not block it; close the idea first to turn its missed ones into skipped.
bool inboxIdeaCanDelete(InboxIdeaView view) =>
    !view.sessions.any((s) => s.status == InboxSessionStatus.upcoming);

/// Sessions that stay on Day when the idea is deleted: every one that is not
/// dropped (a dropped session is already deleted).
int _pastSessions(InboxIdeaView view) =>
    view.sessions.where((s) => s.status != InboxSessionStatus.dropped).length;
