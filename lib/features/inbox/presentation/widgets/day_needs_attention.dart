import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_task_tile.dart';

/// A compact, conditional Day-surface projection of only urgent Inbox work.
/// General captures stay in the dedicated Inbox route.
class DayNeedsAttention extends ConsumerWidget {
  const DayNeedsAttention({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(dayAttentionProvider);
    return attention.when(
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
                for (final item in items)
                  InboxTaskTile(
                    key: ValueKey('day-attention-${item.task.id}'),
                    item: item,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
