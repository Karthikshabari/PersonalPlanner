import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../review/domain/reschedule_chain.dart';

/// Where the chain of [taskId] started, or null for a block never moved.
final originalPlanTextProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, taskId) async {
      final links = await ref
          .read(appDatabaseProvider)
          .taskDao
          .getRescheduleRelatives([taskId]);
      final byId = {for (final link in links) link.id: link};
      final targets = {for (final link in links) link.rescheduledToId};
      for (final link in links) {
        if (targets.contains(link.id)) continue;
        final move = rescheduleMoveOf(link.id, byId);
        if (move != null) return originallyPlannedText(move);
      }
      return null;
    });

/// Read-only editor line for a block that was moved at least once.
class OriginalPlanLine extends ConsumerWidget {
  const OriginalPlanLine({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(originalPlanTextProvider(taskId)).value;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        key: const ValueKey('original-plan-line'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppThemeTokens.of(context).textMuted),
      ),
    );
  }
}
