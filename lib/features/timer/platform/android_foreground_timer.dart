import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Bridges the running timer to an Android foreground service so the
/// persistent notification (with Pause/Stop actions) survives backgrounding
/// (planner.md Chunk 6 #10). Every call is a no-op on non-Android platforms.
class AndroidForegroundTimer {
  static const int serviceId = 4202;
  static const String pauseButtonId = 'timer_pause';
  static const String stopButtonId = 'timer_stop';
  static const String _startedAtKey = 'timer_started_at_ms';
  static const String _titleKey = 'timer_title';
  static const String _pendingActionKey = 'timer_pending_action';
  static const String _pendingActionAtKey = 'timer_pending_action_at_ms';

  /// Set by the app shell; invoked on the main isolate when the user taps a
  /// notification button.
  static void Function(String action)? onButtonAction;

  static bool get supported => Platform.isAndroid;

  static bool _initialized = false;
  static String _currentTitle = '';

  Future<void> init() async {
    if (!supported || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'personal_planner_timer',
        channelName: 'Running timer',
        channelDescription: 'Shows the task timer while it runs',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
      ),
    );
    // Button presses fire in the background isolate; the handler forwards
    // them here via sendDataToMain.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _initialized = true;
  }

  void _onTaskData(dynamic data) {
    if (data is Map && data['timerAction'] is String) {
      onButtonAction?.call(data['timerAction'] as String);
    }
  }

  Future<bool> start({required String taskTitle}) async {
    if (!supported) return true;
    _currentTitle = taskTitle;
    try {
      await FlutterForegroundTask.saveData(
        key: _startedAtKey,
        value: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      await FlutterForegroundTask.saveData(key: _titleKey, value: taskTitle);
      final result = await FlutterForegroundTask.startService(
        serviceId: serviceId,
        serviceTypes: [ForegroundServiceTypes.specialUse],
        notificationTitle: 'Timer running',
        notificationText: taskTitle,
        notificationButtons: const [
          NotificationButton(id: pauseButtonId, text: 'Pause'),
          NotificationButton(id: stopButtonId, text: 'Stop'),
        ],
        callback: foregroundTimerCallback,
      );
      return result is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Refreshes the elapsed time in the persistent notification.
  Future<void> updateElapsed(String clockLabel) async {
    if (!supported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationText: '$_currentTitle  $clockLabel',
        );
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    if (!supported) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    await FlutterForegroundTask.removeData(key: _startedAtKey);
    await FlutterForegroundTask.removeData(key: _titleKey);
    await FlutterForegroundTask.removeData(key: _pendingActionKey);
    await FlutterForegroundTask.removeData(key: _pendingActionAtKey);
  }

  static Future<String?> takePendingAction() async {
    if (!supported) return null;
    final action = await FlutterForegroundTask.getData<String>(key: _pendingActionKey);
    if (action == null) return null;
    await FlutterForegroundTask.removeData(key: _pendingActionKey);
    await FlutterForegroundTask.removeData(key: _pendingActionAtKey);
    return action;
  }
}

/// Entry point of the background isolate that owns the notification.
@pragma('vm:entry-point')
void foregroundTimerCallback() {
  FlutterForegroundTask.setTaskHandler(_ForegroundTimerHandler());
}

class _ForegroundTimerHandler extends TaskHandler {
  DateTime? _startedAt;
  String _title = 'Timer running';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final startedMs = await FlutterForegroundTask.getData<int>(key: 'timer_started_at_ms');
    final title = await FlutterForegroundTask.getData<String>(key: 'timer_title');
    _startedAt = startedMs == null
        ? timestamp
        : DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true).toLocal();
    _title = title ?? _title;
    await _updateNotification(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_updateNotification(timestamp));
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    unawaited(FlutterForegroundTask.saveData(
      key: 'timer_pending_action',
      value: id,
    ));
    unawaited(FlutterForegroundTask.saveData(
      key: 'timer_pending_action_at_ms',
      value: DateTime.now().toUtc().millisecondsSinceEpoch,
    ));
    FlutterForegroundTask.sendDataToMain({'timerAction': id});
  }

  Future<void> _updateNotification(DateTime timestamp) async {
    final start = _startedAt ?? timestamp;
    final elapsed = timestamp.difference(start).inSeconds.clamp(0, 1 << 31);
    final h = elapsed ~/ 3600;
    final m = (elapsed % 3600) ~/ 60;
    final s = elapsed % 60;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Timer running',
      notificationText: '$_title  ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
    );
  }
}
