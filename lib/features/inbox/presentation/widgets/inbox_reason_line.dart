import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../review/providers/review_providers.dart';
import '../../providers/inbox_provider.dart';

/// "N missed sessions from the Inbox have no reason yet." with a button to
/// Review, where reasons are written. Shown only while N > 0. The Inbox never
/// writes a reason itself.
class InboxReasonLine extends ConsumerWidget {
  const InboxReasonLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(
      inboxBoardProvider.select((board) => board.value?.reasonsMissing),
    );
    final count = missing?.count ?? 0;
    final latest = missing?.latestDate;
    if (count == 0 || latest == null) return const SizedBox.shrink();
    final tokens = AppThemeTokens.of(context);
    final date = parseIsoDate(latest);
    final text = count == 1
        ? '1 missed session from the Inbox has no reason yet. '
              'Reasons are written in Review.'
        : '$count missed sessions from the Inbox have no reason yet. '
              'Reasons are written in Review.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppSurface(
        key: const ValueKey('inbox-reason-line'),
        color: tokens.surfaceSubtle,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          runSpacing: AppSpacing.xs,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            Semantics(
              button: true,
              label:
                  'Open Review on ${DateFormat('EEEE, MMMM d').format(date)}',
              excludeSemantics: true,
              child: TextButton(
                key: const ValueKey('inbox-open-review'),
                onPressed: () {
                  ref.read(selectedReviewDateProvider.notifier).state = date;
                  ref.read(selectedWeekStartProvider.notifier).state =
                      startOfWeek(date);
                  context.go('/review');
                },
                child: const Text('Open Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
