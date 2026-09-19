import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/password_policy.dart';

/// Live checklist of the password rules this build guarantees.
///
/// Only [PlannerPasswordPolicy.rules] are shown, so the guidance can never
/// promise a rule the app does not enforce. Satisfied and unsatisfied rules
/// differ by icon *shape* and by semantics, not only by colour, and an
/// unsatisfied rule stays neutral instead of red until the user submits.
class PasswordRequirementsIndicator extends StatelessWidget {
  const PasswordRequirementsIndicator({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      container: true,
      label: 'Password requirements',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your password needs:',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final rule in PlannerPasswordPolicy.rules)
            _RequirementLine(
              key: ValueKey<String>('password-rule-${rule.id}'),
              label: rule.label,
              met: rule.isSatisfied(password),
            ),
        ],
      ),
    );
  }
}

class _RequirementLine extends StatelessWidget {
  const _RequirementLine({super.key, required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs / 2),
      child: Semantics(
        label: '$label: ${met ? 'met' : 'not met yet'}',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                met ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: met ? tokens.success : tokens.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: met ? tokens.textPrimary : tokens.textSecondary,
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
