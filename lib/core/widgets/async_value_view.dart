import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_panel.dart';

/// Small presentation boundary for provider-backed reads. It deliberately
/// keeps loading, data, and failure distinct so a failed read cannot become a
/// plausible empty or zero-valued screen.
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool compact;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => ErrorPanel(
      message: friendlyErrorMessage(error),
      onRetry: onRetry,
      compact: compact,
    ),
    data: builder,
  );
}
