import 'package:flutter/widgets.dart';

import 'weekly_review_style.dart';

/// Animates its own height when [child] changes size (200 ms, ease-out). With
/// reduced motion it is just the child: `AnimatedSize` with a zero duration
/// asserts in debug builds when the child resizes.
class ReviewAnimatedSize extends StatelessWidget {
  const ReviewAnimatedSize({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: WeeklyStyle.content,
      curve: WeeklyStyle.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
