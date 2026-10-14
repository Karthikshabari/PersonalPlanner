import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/models/inbox_item.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_theme_tokens.dart';
import '../../../../../core/widgets/error_panel.dart';
import '../../../../inbox/presentation/widgets/day_needs_attention.dart';
import '../../../../inbox/providers/inbox_provider.dart';
import '../../../../review/presentation/widgets/review_animated_size.dart';
import '../day_style.dart';
import 'attention_groups.dart';
import 'day_attention_list.dart';

export '../../../../inbox/presentation/widgets/day_needs_attention.dart'
    show dayAttentionExpandedProvider;

/// Rows shown without a collapse toggle in the medium strip.
const _alwaysShownCount = 3;

/// Height a row is assumed to need when sizing the strip body. Taller rows
/// (large text) simply scroll inside the strip.
const _estimatedRowHeight = 64.0;

const _stripHeaderHeight = 48.0;

/// Heights assumed for the group headings and the "Move all to today" line
/// when sizing the strip body.
const _estimatedGroupHeaderHeight = 32.0;
const _moveAllHeight = 48.0;

/// One tinted surface for the overdue banner and strip: the amber warning
/// colour at 12% over the surface (no Opacity layer).
Color _amberTint(BuildContext context) {
  final tokens = AppThemeTokens.of(context);
  return Color.alphaBlend(
    tokens.warning.withValues(alpha: 0.12),
    tokens.surface,
  );
}

String _title(int count) => 'Needs attention · $count';

/// The clock Day's attention list reads, with the test fallback.
DateTime _watchNow(WidgetRef ref) =>
    ref.watch(inboxClockProvider.select((clock) => clock.value)) ??
    ref.read(inboxNowFactoryProvider)();

/// Reads [dayAttentionProvider] the way Day always has: the list is rebuilt
/// every minute, so rows (and any dialog opened from one) stay mounted while
/// it reloads.
class _AttentionSource extends ConsumerWidget {
  const _AttentionSource({
    required this.builder,
    this.empty = const SizedBox.shrink(),
  });

  final Widget Function(BuildContext context, List<InboxItem> items) builder;

  /// Shown when nothing needs attention.
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(dayAttentionProvider);
    return attention.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          0,
        ),
        child: ErrorPanel(
          message: friendlyErrorMessage(error),
          onRetry: () => ref.invalidate(dayAttentionProvider),
          compact: true,
        ),
      ),
      data: (items) => items.isEmpty ? empty : builder(context, items),
    );
  }
}

/// Compact: one amber line ("13 overdue · Review") that opens the list in a
/// draggable bottom sheet.
class DayAttentionBanner extends StatelessWidget {
  const DayAttentionBanner({super.key});

  @override
  Widget build(BuildContext context) =>
      _AttentionSource(builder: (context, items) => _Banner(items: items));
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.items});

  final List<InboxItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    var overdue = 0;
    var dueToday = 0;
    for (final group in groupAttention(items, _watchNow(ref))) {
      if (group.kind == AttentionGroupKind.dueToday) {
        dueToday += group.items.length;
      } else {
        overdue += group.items.length;
      }
    }
    final text = [
      if (overdue > 0) '$overdue overdue',
      if (dueToday > 0) '$dueToday due today',
      'Review',
    ].join(' · ');
    final radius = BorderRadius.circular(DayStyle.medium(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Material(
        key: const ValueKey('day-needs-attention'),
        color: _amberTint(context),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.warning.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          key: const ValueKey('day-attention-banner'),
          borderRadius: radius,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const _AttentionSheet(),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: tokens.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DayStyle.section(context)
                          .copyWith(color: tokens.textPrimary),
                    ),
                  ),
                  Icon(Icons.expand_less, color: tokens.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact list. It has its own [ScaffoldMessenger] and [Scaffold] so the
/// "Moved to 14:00 · Undo" bar shows inside the sheet: the route's scrim and
/// the sheet itself would cover a bar shown by the page underneath.
class _AttentionSheet extends StatelessWidget {
  const _AttentionSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Builder(
            // Outlives the rows: they hand it to the snack bar.
            builder: (feedbackContext) => _AttentionSource(
              empty: _SheetEmpty(controller: controller),
              builder: (context, items) => DayAttentionList(
                items: items,
                // The sheet covers the timeline, so there is nothing to drop on.
                showDragHandle: false,
                controller: controller,
                scrollKey: const ValueKey('day-attention-sheet-list'),
                leading: const _GrabBar(),
                feedbackContext: feedbackContext,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GrabBar extends StatelessWidget {
  const _GrabBar();

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: tokens.outlineStrong,
            borderRadius: BorderRadius.circular(DayStyle.pill),
          ),
        ),
      ),
    );
  }
}

/// What the sheet shows once the last item has been dealt with.
class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [_GrabBar(), _PanelEmpty()],
    );
  }
}

/// Medium: a card under the header. It collapses to its header line when
/// there are more than three items; the expanded body scrolls inside
/// [maxHeight].
class DayAttentionStrip extends StatelessWidget {
  const DayAttentionStrip({super.key, required this.maxHeight});

  /// The most height the whole strip may take, supplied by the Day layout
  /// (35% of the space below the header).
  final double maxHeight;

  @override
  Widget build(BuildContext context) => _AttentionSource(
    builder: (context, items) => _Strip(items: items, maxHeight: maxHeight),
  );
}

class _Strip extends ConsumerWidget {
  const _Strip({required this.items, required this.maxHeight});

  final List<InboxItem> items;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final collapsible = items.length > _alwaysShownCount;
    // The provider defaults to false (collapsed); a short list is never
    // collapsed, so it only matters when there are more than three rows.
    final expandedFlag = ref.watch(dayAttentionExpandedProvider);
    final expanded = !collapsible || expandedFlag;
    const verticalPadding = AppSpacing.xs;
    const border = 2.0;
    final listCap = math.max(
      0.0,
      maxHeight - _stripHeaderHeight - border - 2 * verticalPadding,
    );
    // Rows, group headings and the "Move all" line; taller content scrolls.
    final groups = groupAttention(items, _watchNow(ref));
    final overdue = items.where((item) => item.isOverdue).length;
    final listHeight = math.min(
      listCap,
      items.length * _estimatedRowHeight +
          groups.length * _estimatedGroupHeaderHeight +
          (overdue >= 2 ? _moveAllHeight : 0),
    );
    final radius = BorderRadius.circular(DayStyle.medium(context));

    final header = SizedBox(
      height: _stripHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: tokens.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _title(items.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DayStyle.section(context),
              ),
            ),
            if (collapsible)
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: tokens.textSecondary,
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        verticalPadding,
        AppSpacing.md,
        verticalPadding,
      ),
      child: ReviewAnimatedSize(
        child: Container(
          key: const ValueKey('day-needs-attention'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _amberTint(context),
            borderRadius: radius,
            border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (collapsible)
                InkWell(
                  key: const ValueKey('day-attention-toggle'),
                  onTap: () =>
                      ref.read(dayAttentionExpandedProvider.notifier).state =
                          !expandedFlag,
                  child: header,
                )
              else
                header,
              if (expanded)
                SizedBox(
                  height: listHeight,
                  child: DayAttentionList(
                    items: items,
                    // The timeline is visible under the strip.
                    showDragHandle: true,
                    showTitle: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanded and large: the list as a card in the right panel, filling the
/// height it is given.
class DayAttentionPanelList extends StatelessWidget {
  const DayAttentionPanelList({super.key});

  @override
  Widget build(BuildContext context) => _AttentionSource(
    empty: const _PanelEmpty(),
    builder: (context, items) => _PanelList(items: items),
  );
}

/// Shown in the panel when nothing needs attention: a line, not a card.
class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty();

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        key: const ValueKey('day-attention-empty'),
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: tokens.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Nothing overdue', style: DayStyle.secondary(context)),
          ),
        ],
      ),
    );
  }
}

class _PanelList extends StatelessWidget {
  const _PanelList({required this.items});

  final List<InboxItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      key: const ValueKey('day-needs-attention'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(DayStyle.medium(context)),
        border: Border.all(color: tokens.outline),
      ),
      child: DayAttentionList(items: items, showDragHandle: true),
    );
  }
}
