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
import '../widgets/overview_week_strip.dart';
import '../widgets/review_animated_size.dart';
import '../widgets/review_layout.dart';
import '../widgets/review_mode_switcher.dart';
import '../widgets/weekly_review_style.dart';

class ReviewOverviewScreen extends ConsumerStatefulWidget {
  const ReviewOverviewScreen({super.key, this.initialWeekly = false});

  /// Opens with the Weekly sub-tab selected (`/review/overview?tab=weekly`).
  final bool initialWeekly;

  @override
  ConsumerState<ReviewOverviewScreen> createState() =>
      _ReviewOverviewScreenState();
}

class _ReviewOverviewScreenState extends ConsumerState<ReviewOverviewScreen> {
  late bool _weekly = widget.initialWeekly;

  @override
  void didUpdateWidget(ReviewOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWeekly != widget.initialWeekly) {
      _weekly = widget.initialWeekly;
    }
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: const [GlobalSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The same rule as the Daily and Weekly reviews: the content
            // column, not the window, decides.
            final wide = ReviewLayout.isWide(constraints.maxWidth);
            return ListView(
              padding: const EdgeInsets.all(ReviewLayout.pagePadding),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ReviewLayout.maxContentWidth,
                    ),
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
                                  expandedInsets: wide ? null : EdgeInsets.zero,
                                  // "Days" and "Weeks" so the labels cannot be
                                  // mistaken for the Daily / Weekly switcher.
                                  segments: const [
                                    ButtonSegment(
                                      value: false,
                                      label: Text('Days'),
                                    ),
                                    ButtonSegment(
                                      value: true,
                                      label: Text('Weeks'),
                                    ),
                                  ],
                                  selected: {_weekly},
                                  onSelectionChanged: (selection) =>
                                      setState(() => _weekly = selection.first),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              // A short cross-fade; the card eases to the new
                              // height instead of jumping.
                              ReviewAnimatedSize(
                                child: AnimatedSwitcher(
                                  duration: _crossFade(context),
                                  switchInCurve: WeeklyStyle.curve,
                                  switchOutCurve: WeeklyStyle.curve,
                                  child: KeyedSubtree(
                                    key: ValueKey(_weekly),
                                    child: _weekly
                                        ? const OverviewWeekStrip()
                                        : OverviewDayStrip(wide: wide),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Duration _crossFade(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 150);
}
