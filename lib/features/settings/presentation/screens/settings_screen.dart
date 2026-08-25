import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../timeline/presentation/providers/grid_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridAsync = ref.watch(gridIntervalProvider);
    final gridInterval =
        gridAsync.value ?? AppConstants.defaultGridMinutes;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Categories'),
              subtitle: const Text('Manage categories and colors'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/categories'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              key: const ValueKey('templates-tile'),
              leading: const Icon(Icons.bookmark_border_outlined),
              title: const Text('Task Templates'),
              subtitle: const Text('Reusable task presets'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/templates'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              key: const ValueKey('grid-interval-tile'),
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Timeline grid interval'),
              subtitle:
                  const Text('Snap spacing for drag, resize and quick create'),
              trailing: DropdownButton<int>(
                key: const ValueKey('grid-interval-dropdown'),
                value: gridInterval,
                items: [
                  for (final minutes in AppConstants.gridOptions)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text('$minutes min'),
                    ),
                ],
                onChanged: (minutes) {
                  if (minutes == null) return;
                  ref
                      .read(gridIntervalProvider.notifier)
                      .setInterval(minutes);
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Card(
            child: ListTile(
              leading: Icon(Icons.dark_mode_outlined),
              title: Text('Appearance'),
              subtitle: Text('Dark theme (default)'),
            ),
          ),
        ],
      ),
    );
  }
}
