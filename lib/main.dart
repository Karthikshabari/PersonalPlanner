import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers/database_provider.dart';
import 'core/router/app_router.dart';
import 'features/recurring/providers/recurring_providers.dart';
import 'features/settings/providers/notification_settings_providers.dart';
import 'features/timer/domain/notification_service.dart';
import 'features/timer/platform/android_foreground_timer.dart';
import 'features/timer/providers/timer_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  try {
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  // Materialize recurring tasks for today + tomorrow on app start
  // (planner.md Chunk 4 #3).
  try {
    final recurrence = container.read(recurrenceServiceProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await recurrence.materializeForDate(today);
    await recurrence.materializeForDate(today.add(const Duration(days: 1)));
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }

  // Daily review reminder + timer foreground service (Chunk 6).
  try {
    await initializeTimezone();
    final notifications = container.read(notificationServiceProvider);
    await notifications.init(onSelect: (payload) {
      appRouter.go(payload ?? NotificationService.reviewRoute);
    });
    final enabled = await container.read(reviewReminderEnabledProvider.future);
    final minutes = await container.read(reviewReminderMinutesProvider.future);
    if (enabled) {
      final armed = await notifications.scheduleDailyReminder(
        hour: minutes ~/ 60,
        minute: minutes % 60,
      );
      if (notifications.schedulingSupported && !armed) {
        await container.read(reviewReminderEnabledProvider.notifier).setEnabled(false);
      }
    }
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  try {
    await AndroidForegroundTimer().init();
    Future<void> handleTimerAction(String action) async {
      final service = container.read(timerServiceProvider);
      if (action == AndroidForegroundTimer.pauseButtonId) {
        await service.pause();
      } else if (action == AndroidForegroundTimer.stopButtonId) {
        await service.stop();
      }
      await AndroidForegroundTimer().stop();
    }
    AndroidForegroundTimer.onButtonAction = handleTimerAction;
    final pendingAction = await AndroidForegroundTimer.takePendingAction();
    if (pendingAction != null) await handleTimerAction(pendingAction);
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PersonalPlannerApp(),
  ));
}
