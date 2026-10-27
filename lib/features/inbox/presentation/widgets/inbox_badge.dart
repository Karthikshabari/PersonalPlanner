import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/inbox_status.dart';

/// The small bordered label used for a session status or a Done outcome. Same
/// container style as `OverdueBadge` / `DueDateBadge`, parameterised by label
/// and colour.
class InboxBadge extends StatelessWidget {
  const InboxBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  /// Status badge of one session. "Now" while a planned session is running.
  factory InboxBadge.session(
    BuildContext context,
    InboxSessionStatus status, {
    required bool started,
  }) {
    final tokens = AppThemeTokens.of(context);
    return switch (status) {
      InboxSessionStatus.upcoming => InboxBadge(
        label: started ? 'Now' : 'Coming up',
        color: tokens.info,
      ),
      InboxSessionStatus.missed => InboxBadge(
        label: 'Missed',
        color: tokens.warning,
      ),
      InboxSessionStatus.done => InboxBadge(
        label: 'Done',
        color: tokens.success,
      ),
      InboxSessionStatus.carried => InboxBadge(
        label: 'Carried over',
        color: tokens.textMuted,
      ),
      InboxSessionStatus.skipped => InboxBadge(
        label: 'Skipped',
        color: tokens.textMuted,
      ),
      InboxSessionStatus.dropped => InboxBadge(
        label: 'Dropped',
        color: tokens.textMuted,
      ),
    };
  }

  /// The outcome chip of a Done row (Finished, Closed, Let go or an
  /// Experiment label).
  factory InboxBadge.outcome(BuildContext context, String chip) {
    final tokens = AppThemeTokens.of(context);
    final color = chip == 'Finished'
        ? tokens.success
        : chip.startsWith('Experiment')
        ? tokens.info
        : tokens.textMuted;
    return InboxBadge(label: chip, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}
