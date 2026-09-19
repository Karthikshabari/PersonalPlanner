import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';

/// One compact fact shown before the very first cloud project is created.
class CloudSetupFact {
  const CloudSetupFact({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

/// Facts Personal Planner can stand behind.
///
/// The storage wording is deliberately qualitative: no repository document,
/// migration or measurement in this project supports a numeric "30–40 MB"
/// estimate, so no number is presented as fact. Supabase's own plan limits are
/// referred to instead of hard-coding quotas that change over time.
const List<CloudSetupFact> cloudSetupPreflightFacts = <CloudSetupFact>[
  CloudSetupFact(
    icon: Icons.cloud_queue,
    text: 'Creates 1 Supabase project',
  ),
  CloudSetupFact(
    icon: Icons.auto_fix_high_outlined,
    text: 'Personal Planner configures the project automatically',
  ),
  CloudSetupFact(
    icon: Icons.data_usage_outlined,
    text:
        'Uses a small amount of your Supabase project storage; your plan\'s '
        'limits still apply',
  ),
  CloudSetupFact(
    icon: Icons.shield_outlined,
    text: 'Nothing is created until you continue',
  ),
];

const String cloudSetupPreflightTitle = 'Set up cloud storage';
const String cloudSetupPreflightBody =
    'Personal Planner will create a Supabase project in your account and '
    'configure it automatically so your Planner data can sync across devices.';
const String cloudSetupPreflightCancelLabel = 'Cancel';
const String cloudSetupPreflightContinueLabel = 'Continue with Supabase';

/// Confirms the first cloud project creation.
///
/// Returns true only when the user explicitly continues; dismissing the dialog
/// (cancel, back, tap-away) returns false and creates nothing. No provisioning
/// work happens here — the caller runs the exact same `startSetup` flow it
/// always did.
Future<bool> showCloudSetupPreflight(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _CloudSetupPreflightDialog(),
  );
  return confirmed ?? false;
}

class _CloudSetupPreflightDialog extends StatelessWidget {
  const _CloudSetupPreflightDialog();

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      key: const ValueKey('cloud-setup-preflight'),
      // The dialog keeps a comfortable reading width on desktop and still fits
      // a phone viewport, and the body scrolls when text scaling is large.
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? AppSpacing.lg : AppSpacing.xxxl,
        vertical: AppSpacing.xxl,
      ),
      scrollable: true,
      title: const Text(cloudSetupPreflightTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(cloudSetupPreflightBody),
            const SizedBox(height: AppSpacing.md),
            for (final fact in cloudSetupPreflightFacts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(fact.icon, size: 18, color: tokens.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(fact.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cloud-preflight-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(cloudSetupPreflightCancelLabel),
        ),
        FilledButton(
          key: const ValueKey('cloud-preflight-continue'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(cloudSetupPreflightContinueLabel),
        ),
      ],
    );
  }
}
