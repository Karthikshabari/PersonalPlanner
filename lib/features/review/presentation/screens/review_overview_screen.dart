import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/global_search_action.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../providers/review_providers.dart';
import '../widgets/overview_day_strip.dart';
import '../widgets/review_mode_switcher.dart';

class ReviewOverviewScreen extends ConsumerStatefulWidget {
  const ReviewOverviewScreen({super.key});

  @override
  ConsumerState<ReviewOverviewScreen> createState() =>
      _ReviewOverviewScreenState();
}

class _ReviewOverviewScreenState extends ConsumerState<ReviewOverviewScreen> {
  bool _weekly = false;

  void _onMode(String mode) {
    if (mode == 'daily') {
      if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
        context.go('/review');
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/review');
      }
    } else if (mode == 'weekly') {
      ref.read(selectedWeekStartProvider.notifier).state = startOfWeek(
        ref.read(selectedReviewDateProvider),
      );
      openReviewPath(context, '/review/weekly');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.all(
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.lg,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ReviewModeSwitcher(
                          weekly: false,
                          overview: true,
                          onChanged: _onMode,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SegmentedButton<bool>(
                                key: const ValueKey('overview-subtabs'),
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Daily'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Weekly'),
                                  ),
                                ],
                                selected: {_weekly},
                                onSelectionChanged: (selection) =>
                                    setState(() => _weekly = selection.first),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (_weekly)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 26,
                                  horizontal: 8,
                                ),
                                child: Text(
                                  'Weekly overview comes in the weekly round.',
                                  key: const ValueKey(
                                    'overview-weekly-placeholder',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: tokens.textMuted,
                                  ),
                                ),
                              )
                            else
                              const OverviewDayStrip(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
