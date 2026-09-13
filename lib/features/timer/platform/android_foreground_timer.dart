import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Narrow injectable seam for the durable native-action envelope. It keeps
/// action retry/ack tests platform independent without introducing a second
/// timer-state store; production still uses the foreground-task key/value
/// storage and SQLite remains authoritative for timer state.
abstract interface class PendingForegroundTimerActionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> remove();
}

/// Android foreground presentation for a persisted locally-owned session.
/// SQLite remains authoritative; native storage contains only display/action
/// metadata for the exact running segment.
class AndroidForegroundTimer {
  static const int serviceId = 4202;
  static const String pauseButtonId = 'timer_pause';
  static const String stopButtonId = 'timer_stop';
  static const String _titleKey = 'timer_title';
  static const String _taskIdKey = 'timer_task_id';
  static const String _sessionIdKey = 'timer_session_id';
  static const String _accountIdKey = 'timer_account_id';
  static const String _ownerDeviceIdKey = 'timer_owner_device_id';
  static const String _runningSinceKey = 'timer_running_since_ms';
  static const String _durationSecKey = 'timer_duration_sec';
  static const String _stateRevisionKey = 'timer_state_revision';
  static const String _pendingActionKey = 'timer_pending_action_envelope';

  static Future<void> Function(PendingForegroundTimerAction action)?
  onButtonAction;

  @visibleForTesting
  static PendingForegroundTimerActionStore? pendingActionStore;

  /// Presentation-only reflection of the durable envelope. SQLite remains
  /// authoritative; this lets controls freeze at the original action time
  /// while a failed native transition is awaiting retry/restart.
  static final ValueNotifier<PendingForegroundTimerAction?> pendingAction =
      ValueNotifier<PendingForegroundTimerAction?>(null);
  static Future<void>? _activeButtonAction;
  static bool get supported => Platform.isAndroid;
  static bool _initialized = false;
  static String? accountScope;

  static void setAccountScope(String? accountId) => accountScope = accountId;

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
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _initialized = true;
  }

  void _onTaskData(dynamic data) {
    if (data is! Map || data['timerAction'] is! Map) return;
    final action = PendingForegroundTimerAction.fromJson(
      Map<String, dynamic>.from(data['timerAction'] as Map),
    );
    if (action == null) return;
    pendingAction.value = action;
    final callback = onButtonAction;
    if (callback == null || _activeButtonAction != null) return;
    final running = callback(action);
    _activeButtonAction = running;
    unawaited(
      running.whenComplete(() {
        if (identical(_activeButtonAction, running)) {
          _activeButtonAction = null;
        }
      }),
    );
  }

  static Future<void> detachButtonHandler() async {
    onButtonAction = null;
    await _activeButtonAction;
  }

  Future<bool> start({
    required String taskTitle,
    required String taskId,
    required String sessionId,
    required String ownerDeviceId,
    required DateTime runningSince,
    required int durationSec,
    required int stateRevision,
  }) async {
    if (!supported) return true;
    try {
      // A native action is durable until the matching database transition is
      // acknowledged or proven stale. Starting a new notification must never
      // erase that evidence or make its original timestamp unretryable.
      if (await takePendingAction() != null) return false;
      await Future.wait([
        FlutterForegroundTask.saveData(key: _titleKey, value: taskTitle),
        FlutterForegroundTask.saveData(key: _taskIdKey, value: taskId),
        FlutterForegroundTask.saveData(key: _sessionIdKey, value: sessionId),
        FlutterForegroundTask.saveData(
          key: _ownerDeviceIdKey,
          value: ownerDeviceId,
        ),
        FlutterForegroundTask.saveData(
          key: _runningSinceKey,
          value: runningSince.toUtc().millisecondsSinceEpoch,
        ),
        FlutterForegroundTask.saveData(
          key: _durationSecKey,
          value: durationSec,
        ),
        FlutterForegroundTask.saveData(
          key: _stateRevisionKey,
          value: stateRevision,
        ),
        _removePendingEnvelope(),
      ]);
      pendingAction.value = null;
      final account = accountScope;
      if (account != null) {
        await FlutterForegroundTask.saveData(
          key: _accountIdKey,
          value: account,
        );
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: serviceId,
        serviceTypes: [ForegroundServiceTypes.specialUse],
        notificationTitle: 'Timer running',
        notificationText: taskTitle,
        notificationIcon: const NotificationIcon(
          metaDataName: 'personal_planner_timer_icon',
        ),
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

  /// Stops only the service. The pending envelope remains durable so failed
  /// main-isolate handling can be retried at the original action timestamp.
  Future<void> stopService() async {
    if (!supported) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  /// Targeted cleanup prevents a late acknowledgement clearing a newer timer.
  Future<void> clearSession(String sessionId) async {
    if (!supported) return;
    final current = await FlutterForegroundTask.getData<String>(
      key: _sessionIdKey,
    );
    if (current != sessionId) return;
    await stopService();
    await Future.wait([
      FlutterForegroundTask.removeData(key: _titleKey),
      FlutterForegroundTask.removeData(key: _taskIdKey),
      FlutterForegroundTask.removeData(key: _sessionIdKey),
      FlutterForegroundTask.removeData(key: _accountIdKey),
      FlutterForegroundTask.removeData(key: _ownerDeviceIdKey),
      FlutterForegroundTask.removeData(key: _runningSinceKey),
      FlutterForegroundTask.removeData(key: _durationSecKey),
      FlutterForegroundTask.removeData(key: _stateRevisionKey),
    ]);
  }

  Future<void> acknowledgePendingAction(String actionId) async {
    if (!supported && pendingActionStore == null) return;
    final raw = await _readPendingEnvelope();
    if (raw == null) return;
    final pending = PendingForegroundTimerAction.fromJsonString(raw);
    if (pending?.actionId == actionId) {
      await _removePendingEnvelope();
      pendingAction.value = null;
    }
  }

  static Future<PendingForegroundTimerAction?> takePendingAction() async {
    if (!supported && pendingActionStore == null) return null;
    final raw = await _readPendingEnvelope();
    final pending = raw == null
        ? null
        : PendingForegroundTimerAction.fromJsonString(raw);
    pendingAction.value = pending;
    return pending;
  }

  /// Written before the native service stops. A failed database transition
  /// deliberately leaves this exact envelope in place for retry/restart.
  static Future<void> persistPendingAction(
    PendingForegroundTimerAction action,
  ) async {
    await _writePendingEnvelope(jsonEncode(action.toJson()));
    pendingAction.value = action;
  }

  static Future<String?> _readPendingEnvelope() {
    final store = pendingActionStore;
    return store?.read() ??
        FlutterForegroundTask.getData<String>(key: _pendingActionKey);
  }

  static Future<void> _writePendingEnvelope(String value) {
    final store = pendingActionStore;
    return store?.write(value) ??
        FlutterForegroundTask.saveData(key: _pendingActionKey, value: value);
  }

  static Future<void> _removePendingEnvelope() {
    final store = pendingActionStore;
    return store?.remove() ??
        FlutterForegroundTask.removeData(key: _pendingActionKey);
  }
}

class PendingForegroundTimerAction {
  final String actionId;
  final String action;
  final String? taskId;
  final String? sessionId;
  final String? accountId;
  final String? ownerDeviceId;
  final DateTime? expectedRunningSince;
  final int? expectedDurationSec;
  final int? expectedStateRevision;
  final DateTime occurredAt;

  const PendingForegroundTimerAction({
    required this.actionId,
    required this.action,
    this.taskId,
    this.sessionId,
    this.accountId,
    this.ownerDeviceId,
    this.expectedRunningSince,
    this.expectedDurationSec,
    this.expectedStateRevision,
    required this.occurredAt,
  });

  Map<String, dynamic> toJson() => {
    'action_id': actionId,
    'action': action,
    'task_id': taskId,
    'session_id': sessionId,
    'account_id': accountId,
    'owner_device_id': ownerDeviceId,
    'expected_running_since_ms': expectedRunningSince
        ?.toUtc()
        .millisecondsSinceEpoch,
    'expected_duration_sec': expectedDurationSec,
    'expected_state_revision': expectedStateRevision,
    'occurred_at_ms': occurredAt.toUtc().millisecondsSinceEpoch,
  };

  static PendingForegroundTimerAction? fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } on FormatException {
      return null;
    }
  }

  static PendingForegroundTimerAction? fromJson(Map<String, dynamic> json) {
    final actionId = json['action_id'];
    final action = json['action'];
    final occurredAtMs = json['occurred_at_ms'];
    if (actionId is! String || action is! String || occurredAtMs is! int) {
      return null;
    }
    final runningSinceMs = json['expected_running_since_ms'];
    final duration = json['expected_duration_sec'];
    final revision = json['expected_state_revision'];
    return PendingForegroundTimerAction(
      actionId: actionId,
      action: action,
      taskId: json['task_id'] as String?,
      sessionId: json['session_id'] as String?,
      accountId: json['account_id'] as String?,
      ownerDeviceId: json['owner_device_id'] as String?,
      expectedRunningSince: runningSinceMs is int
          ? DateTime.fromMillisecondsSinceEpoch(runningSinceMs, isUtc: true)
          : null,
      expectedDurationSec: duration is int ? duration : null,
      expectedStateRevision: revision is int ? revision : null,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        occurredAtMs,
        isUtc: true,
      ),
    );
  }
}

@pragma('vm:entry-point')
void foregroundTimerCallback() {
  FlutterForegroundTask.setTaskHandler(_ForegroundTimerHandler());
}

class _ForegroundTimerHandler extends TaskHandler {
  DateTime? _runningSince;
  int _durationSec = 0;
  int? _stateRevision;
  String _title = 'Timer running';
  bool _actionInProgress = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final runningSinceMs = await FlutterForegroundTask.getData<int>(
      key: 'timer_running_since_ms',
    );
    _durationSec =
        await FlutterForegroundTask.getData<int>(key: 'timer_duration_sec') ??
        0;
    _stateRevision = await FlutterForegroundTask.getData<int>(
      key: 'timer_state_revision',
    );
    _title =
        await FlutterForegroundTask.getData<String>(key: 'timer_title') ??
        _title;
    _runningSince = runningSinceMs == null
        ? timestamp.toUtc()
        : DateTime.fromMillisecondsSinceEpoch(runningSinceMs, isUtc: true);
    await _updateNotification(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) =>
      unawaited(_updateNotification(timestamp));

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (_actionInProgress) return;
    _actionInProgress = true;
    unawaited(_handleButton(id).whenComplete(() => _actionInProgress = false));
  }

  Future<void> _handleButton(String id) async {
    final now = DateTime.now().toUtc();
    final sessionId = await FlutterForegroundTask.getData<String>(
      key: 'timer_session_id',
    );
    final action = PendingForegroundTimerAction(
      actionId: '${now.microsecondsSinceEpoch}:$id:${sessionId ?? ''}',
      action: id,
      taskId: await FlutterForegroundTask.getData<String>(key: 'timer_task_id'),
      sessionId: sessionId,
      accountId: await FlutterForegroundTask.getData<String>(
        key: 'timer_account_id',
      ),
      ownerDeviceId: await FlutterForegroundTask.getData<String>(
        key: 'timer_owner_device_id',
      ),
      expectedRunningSince: _runningSince,
      expectedDurationSec: _durationSec,
      expectedStateRevision: _stateRevision,
      occurredAt: now,
    );
    await AndroidForegroundTimer.persistPendingAction(action);
    await FlutterForegroundTask.stopService();
    FlutterForegroundTask.sendDataToMain({'timerAction': action.toJson()});
  }

  Future<void> _updateNotification(DateTime timestamp) async {
    final runningSince = _runningSince ?? timestamp.toUtc();
    final seconds =
        _durationSec +
        timestamp.toUtc().difference(runningSince).inSeconds.clamp(0, 1 << 31);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Timer running',
      notificationText:
          '$_title  ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
    );
  }
}
