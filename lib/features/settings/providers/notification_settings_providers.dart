import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../sync/data/secure_session_storage.dart';
import '../../timer/domain/notification_service.dart';

const String reminderEnabledKey = 'review_reminder_enabled';
const String reminderTimeKey = 'review_reminder_time';
const String notificationPermissionAttemptedKey =
    'personal_planner.notification_permission_attempted.v1';
const int defaultReminderMinutes = 21 * 60; // 21:00 per planner.md Chunk 6 #13

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final notificationPermissionAttemptStoreProvider =
    Provider<SecureKeyValueStore>((ref) => FlutterSecureKeyValueStore());

final notificationPermissionControllerProvider =
    Provider<NotificationPermissionController>((ref) {
      return NotificationPermissionController(
        notifications: ref.watch(notificationServiceProvider),
        store: ref.watch(notificationPermissionAttemptStoreProvider),
      );
    });

/// One-time Android notification capability request, independent of every
/// notification feature's own enabled preference.
class NotificationPermissionController {
  NotificationPermissionController({
    required this.notifications,
    required this.store,
    bool Function()? runtimePermissionRequired,
  }) : _runtimePermissionRequired =
           runtimePermissionRequired ?? (() => Platform.isAndroid);

  final NotificationPermissionGateway notifications;
  final SecureKeyValueStore store;
  final bool Function() _runtimePermissionRequired;
  Future<bool>? _inFlight;

  Future<bool> ensureForFeatureUse() {
    return _inFlight ??= _ensure().whenComplete(() => _inFlight = null);
  }

  Future<bool> _ensure() async {
    if (!_runtimePermissionRequired()) return true;
    if (await notifications.notificationsEnabled()) return true;
    if (await store.containsKey(key: notificationPermissionAttemptedKey)) {
      return false;
    }
    // Persist before handing control to Android so denial, process death, or a
    // plugin failure cannot create a prompt loop on every launch/action.
    await store.write(key: notificationPermissionAttemptedKey, value: '1');
    return notifications.requestPermission();
  }
}

/// Whether the daily review reminder is enabled (default: on).
final reviewReminderEnabledProvider =
    AsyncNotifierProvider<ReviewReminderEnabledNotifier, bool>(
      ReviewReminderEnabledNotifier.new,
    );

class ReviewReminderEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(reminderEnabledKey))).getSingleOrNull();
    return row?.value != 'false'; // enabled unless explicitly disabled
  }

  Future<void> setEnabled(bool value) async {
    final previous = state.value ?? true;
    try {
      if (value && ref.read(notificationServiceProvider).schedulingSupported) {
        await ref
            .read(notificationPermissionControllerProvider)
            .ensureForFeatureUse();
      }
      // Optimistic update for the UI…
      state = AsyncData(value);
      await _persist(value);
      // …then converge to the persisted truth (heals any racing initial
      // build that read a pre-write snapshot).
      ref.invalidateSelf();
      await future;

      await _apply();
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> _persist(bool value) async {
    final db = ref.watch(appDatabaseProvider);
    await db.customStatement(
      'INSERT INTO app_settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [reminderEnabledKey, '$value'],
    );
  }

  Future<bool> _apply() async {
    if (!ref.read(notificationServiceProvider).schedulingSupported) return true;
    if (!(state.value ?? true)) {
      await ref.read(notificationServiceProvider).cancelReminder();
      return true;
    }
    final minutes =
        ref.read(reviewReminderMinutesProvider).value ?? defaultReminderMinutes;
    return ref
        .read(notificationServiceProvider)
        .scheduleDailyReminder(hour: minutes ~/ 60, minute: minutes % 60);
  }
}

/// Reminder time-of-day in minutes since midnight (default 21:00).
final reviewReminderMinutesProvider =
    AsyncNotifierProvider<ReviewReminderMinutesNotifier, int>(
      ReviewReminderMinutesNotifier.new,
    );

class ReviewReminderMinutesNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final db = ref.watch(appDatabaseProvider);
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(reminderTimeKey))).getSingleOrNull();
    final parsed = int.tryParse(row?.value ?? '');
    if (parsed == null || parsed < 0 || parsed > 24 * 60 - 1) {
      return defaultReminderMinutes;
    }
    return parsed;
  }

  Future<void> setMinutes(int minutes) async {
    final effective = minutes.clamp(0, 24 * 60 - 1);
    final previous = state.value ?? defaultReminderMinutes;
    state = AsyncData(effective);
    try {
      final db = ref.watch(appDatabaseProvider);
      await db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [reminderTimeKey, '$effective'],
      );
      ref.invalidateSelf();
      await future;

      if (ref.read(reviewReminderEnabledProvider).value ?? true) {
        if (!ref.read(notificationServiceProvider).schedulingSupported) return;
        await ref
            .read(notificationServiceProvider)
            .scheduleDailyReminder(
              hour: effective ~/ 60,
              minute: effective % 60,
            );
      }
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
