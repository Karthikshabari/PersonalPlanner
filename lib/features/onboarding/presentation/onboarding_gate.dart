import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_panel.dart';
import '../providers/onboarding_provider.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends ConsumerWidget {
  final Widget child;

  const OnboardingGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(onboardingCompletedProvider);
    return completed.when(
      loading: () => const _OnboardingLoading(),
      error: (error, _) => Scaffold(
        body: ErrorPanel(
          message: friendlyErrorMessage(error),
          onRetry: () => ref.invalidate(onboardingCompletedProvider),
        ),
      ),
      data: (isComplete) => isComplete
          ? child
          : OnboardingScreen(
              onComplete: () =>
                  ref.read(onboardingCompletedProvider.notifier).complete(),
            ),
    );
  }
}

class _OnboardingLoading extends StatelessWidget {
  const _OnboardingLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
