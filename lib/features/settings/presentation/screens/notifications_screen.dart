import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/widgets/time_picker_24h.dart';
import '../../providers/notification_settings_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';

/// Settings → Notifications (planner.md Chunk 6 #14): enable/disable the
/// daily review reminder and pick its time. Stored in `app_settings`.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(reviewReminderEnabledProvider);
    final minutesAsync = ref.watch(reviewReminderMinutesProvider);
    if (enabledAsync.hasError || minutesAsync.hasError) {
      final error = enabledAsync.hasError
          ? enabledAsync.error!
          : minutesAsync.error!;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: const [SyncStatusAction()],
        ),
        body: ErrorPanel(
          message: friendlyErrorMessage(error),
          onRetry: () {
            ref.invalidate(reviewReminderEnabledProvider);
            ref.invalidate(reviewReminderMinutesProvider);
          },
        ),
      );
    }
    if (!enabledAsync.hasValue || !minutesAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final enabled = enabledAsync.requireValue;
    final minutes = minutesAsync.requireValue;
    final timeLabel = DateFormat('HH:mm')
        .format(DateTime(2026, 1, 1, minutes ~/ 60, minutes % 60));
    final nativeScheduling = ref
        .watch(notificationServiceProvider)
        .schedulingSupported;
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: const [SyncStatusAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl,
          ),
          children: [
            Card(
              child: SwitchListTile(
                key: const ValueKey('reminder-toggle'),
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Daily review reminder'),
                subtitle: Text(
                  nativeScheduling
                      ? 'Nudges you to fill in the daily review'
                      : 'Only available on Android. This device cannot '
                            'schedule the reminder.',
                ),
                value: enabled && nativeScheduling,
                onChanged: !nativeScheduling
                    ? null
                    : (value) => _runNotificationChange(context, () async {
                        final applied = await ref
                            .read(reviewReminderEnabledProvider.notifier)
                            .setEnabled(value);
                        if (!applied && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Notifications are blocked in system settings',
                              ),
                              action: SnackBarAction(
                                label: 'Open settings',
                                onPressed: ref
                                    .read(notificationServiceProvider)
                                    .openNotificationSettings,
                              ),
                            ),
                          );
                        }
                      }),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                key: const ValueKey('reminder-time-tile'),
                enabled: enabled && nativeScheduling,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Reminder time'),
                trailing: Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () async {
                  final picked = await showTimePicker24h(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: minutes ~/ 60,
                      minute: minutes % 60,
                    ),
                  );
                  if (picked != null && context.mounted) {
                    await _runNotificationChange(
                      context,
                      () => ref
                          .read(reviewReminderMinutesProvider.notifier)
                          .setMinutes(picked.hour * 60 + picked.minute),
                    );
                  }
                },
              ),
            ),
            if (!nativeScheduling) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  'Task reminders fire as desktop notifications on this '
                  'device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _runNotificationChange(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
