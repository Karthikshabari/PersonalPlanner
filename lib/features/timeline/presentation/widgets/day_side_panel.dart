import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/breakpoints.dart';
import '../../../../core/layout/size_class_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../day_context/presentation/day_context_editor.dart';
import '../providers/selected_date_provider.dart';
import 'attention/day_attention_section.dart';
import 'day_layout.dart';
import 'day_style.dart';

/// Right panel of the expanded and large Day layouts: the overdue list and
/// the day's context. The task editor replaces it while it is open.
class DaySidePanel extends StatelessWidget {
  const DaySidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final width = DaySizeClass.of(context) == WindowSizeClass.large
        ? DayLayout.panelWidthLarge
        : DayLayout.panelWidthExpanded;
    return Container(
      key: const ValueKey('day-side-panel'),
      width: width,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.outline)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(child: DayAttentionPanelList()),
          SizedBox(height: AppSpacing.md),
          _DayContextCard(),
        ],
      ),
    );
  }
}

/// The context label and its kind icon come from [DayContextAction], which
/// is also the edit button.
class _DayContextCard extends ConsumerWidget {
  const _DayContextCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final date = ref.watch(selectedDateProvider);
    return Container(
      key: const ValueKey('day-context-card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(DayStyle.medium(context)),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Day context', style: DayStyle.section(context)),
          const SizedBox(height: AppSpacing.xs),
          DayContextAction(date: date, compact: true),
        ],
      ),
    );
  }
}
