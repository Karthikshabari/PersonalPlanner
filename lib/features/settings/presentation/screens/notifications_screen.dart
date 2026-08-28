import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../providers/notification_settings_providers.dart';

/// Settings → Notifications (planner.md Chunk 6 #14): enable/disable the
/// daily review reminder and pick its time. Stored in `app_settings`.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(reviewReminderEnabledProvider).value ?? true;
    final minutes =
        ref.watch(reviewReminderMinutesProvider).value ?? defaultReminderMinutes;
    final timeLabel = DateFormat('HH:mm').format(
        DateTime(2026, 1, 1, minutes ~/ 60, minutes % 60));
    final nativeScheduling =
        ref.watch(notificationServiceProvider).schedulingSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: SwitchListTile(
              key: const ValueKey('reminder-toggle'),
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Daily review reminder'),
              subtitle: const Text('Nudges you to fill in the daily review'),
              value: enabled,
              onChanged: (value) => ref
                  .read(reviewReminderEnabledProvider.notifier)
                  .setEnabled(value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              key: const ValueKey('reminder-time-tile'),
              enabled: enabled,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Reminder time'),
              trailing: Text(timeLabel,
                  style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
                );
                if (picked != null) {
                  await ref
                      .read(reviewReminderMinutesProvider.notifier)
                      .setMinutes(picked.hour * 60 + picked.minute);
                }
              },
            ),
          ),
          if (!nativeScheduling) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'Scheduled notifications are armed on Android/iOS/macOS; on '
                'this platform the setting is stored but no system alarm is '
                'set.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
