import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/widgets/app_surface.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  var _page = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      title: 'Plan your day with confidence',
      body: 'Personal Planner keeps scheduled work, notes, and reviews in one calm timeline.',
      icon: Icons.calendar_month_outlined,
    ),
    _OnboardingPageData(
      title: 'Start with a category',
      body: 'Categories add meaning to your schedule. Use Work, Personal, Health, or create your own.',
      icon: Icons.label_outline,
    ),
    _OnboardingPageData(
      title: 'Create your first task',
      body: 'Double-tap an empty time slot, give the task a title, and save it. Drag or resize it later.',
      icon: Icons.add_task,
    ),
    _OnboardingPageData(
      title: 'Use Inbox for unscheduled ideas',
      body: 'Capture work in Inbox first, then move it onto the timeline when you know where it belongs.',
      icon: Icons.inbox_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      body: ColoredBox(
        color: tokens.canvas,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppSurface(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_page == 0) ...[
                        Align(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Image.asset(
                              'assets/branding/app_logo_with_text.png',
                              width: double.infinity,
                              fit: BoxFit.contain,
                              semanticLabel: 'Personal Planner',
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Icon(
                        page.icon,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        page.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        page.body,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var index = 0; index < _pages.length; index++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: index == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: index == _page
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: ValueKey(
                            isLast ? 'onboarding-start' : 'onboarding-next',
                          ),
                          onPressed: () {
                            if (isLast) {
                              widget.onComplete();
                            } else {
                              setState(() => _page++);
                            }
                          },
                          child: Text(isLast ? 'Start planning' : 'Next'),
                        ),
                      ),
                      if (!isLast) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          key: const ValueKey('onboarding-skip'),
                          onPressed: widget.onComplete,
                          child: const Text('Skip guide'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final String title;
  final String body;
  final IconData icon;

  const _OnboardingPageData({
    required this.title,
    required this.body,
    required this.icon,
  });
}
