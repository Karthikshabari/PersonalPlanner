import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/models/inbox_item.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_task_tile.dart';

const _collapsedCount = 3;

/// Whether the panel shows every item. In memory only, so it starts collapsed
/// after an app restart.
final dayAttentionExpandedProvider = StateProvider<bool>((ref) => false);

/// A compact, conditional Day-surface projection of only urgent Inbox work.
/// General captures stay in the dedicated Inbox route.
class DayNeedsAttention extends ConsumerWidget {
  const DayNeedsAttention({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(dayAttentionProvider);
    // The list is rebuilt every minute; keep the rows (and any dialog opened
    // from one) mounted while it reloads.
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
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final tokens = AppThemeTokens.of(context);
        final expanded = ref.watch(dayAttentionExpandedProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: AppSurface(
            key: const ValueKey('day-needs-attention'),
            padding: EdgeInsets.zero,
            color: tokens.surfaceSubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    0,
                  ),
                  child: Text(
                    'Needs attention · ${items.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (!expanded)
                  for (final item in items.take(_collapsedCount)) _tile(item)
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [for (final item in items) _tile(item)],
                    ),
                  ),
                if (items.length > _collapsedCount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('day-attention-toggle'),
                      onPressed: () =>
                          ref
                                  .read(dayAttentionExpandedProvider.notifier)
                                  .state =
                              !expanded,
                      child: Text(
                        expanded ? 'Show less' : 'Show all (${items.length})',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _tile(InboxItem item) =>
    InboxTaskTile(key: ValueKey('day-attention-${item.task.id}'), item: item);
