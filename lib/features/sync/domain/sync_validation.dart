import 'dart:convert';

import '../../../core/models/timer_session.dart';
import '../../../core/utils/uuid.dart';
import '../../../core/utils/missed_at.dart';
import '../../recurring/domain/rrule_utils.dart';
import '../../task_editor/domain/plan_title_history.dart';
import 'sync_models.dart';

/// A payload rejected at the sync boundary is not a transport failure. It is
/// quarantined/blocked until the data can be repaired, so retries cannot
/// repeatedly apply a malformed row or hide the actual problem.
class SyncValidationException implements Exception {
  final String message;

  const SyncValidationException(this.message);

  @override
  String toString() => message;
}

abstract final class SyncPayloadValidator {
  static const tables = {
    'tasks',
    'categories',
    'subtasks',
    'tags',
    'task_tags',
    'recurring_rules',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'timer_sessions',
    'day_contexts',
  };

  static void validate(SyncRemoteChange change) {
    if (!tables.contains(change.tableName)) {
      throw SyncValidationException(
        'Unsupported remote sync table: ${change.tableName}',
      );
    }
    if (change.operation != 'insert' &&
        change.operation != 'update' &&
        change.operation != 'delete') {
      throw const SyncValidationException('Unsupported remote sync operation');
    }
    if (change.operation == 'delete') {
      _validateIdentity(change);
      return;
    }
    _normalizeLegacyPayload(change);
    _validateIdentity(change);
    final p = change.payload;
    _validateOptionalDateTimes(change.tableName, p);
    switch (change.tableName) {
      case 'tasks':
        _requiredText(p, 'title');
        _requiredEnum(p, 'status', {
          'planned',
          'in_progress',
          'completed',
          'skipped',
          'cancelled',
          'rescheduled',
        });
        _intInRange(p, 'priority', 0, 4);
        _intInRange(p, 'is_inbox', 0, 1);
        if (!p.containsKey('inbox_content_version')) {
          // A v1 feed has no marker. The remote adapter may replace this with
          // the current local source before applying it; validation still
          // accepts the legacy shape without inventing a title.
          p['inbox_content_version'] = 0;
        }
        _intInRange(p, 'inbox_content_version', 0, 1);
        if (p.containsKey('due_date')) {
          _dateOnlyIfPresent(p, 'due_date');
        } else {
          p['due_date'] = null;
        }
        // A durable legacy operation must retain absent fields so the server
        // can merge them over its current canonical row. New payloads always
        // carry both fields and are strictly validated here.
        if (p.containsKey('plan_title_history_json') ||
            p.containsKey('display_plan_change_id')) {
          final historyJson = p['plan_title_history_json'] ?? '[]';
          if (historyJson is! String) {
            throw const SyncValidationException(
              'plan_title_history_json must be JSON text',
            );
          }
          try {
            final history = PlanTitleHistory.decodeJson(historyJson);
            PlanTitleHistory.validate(
              history,
              displayPlanChangeId: p['display_plan_change_id']?.toString(),
              currentTitle: p['title']?.toString() ?? '',
            );
          } on FormatException catch (error) {
            throw SyncValidationException(error.message);
          }
        }
        // estimated_duration_min is a compatibility projection. Validate the
        // source interval below; remote apply recomputes this field rather
        // than allowing a stale/legacy cache value to reject or override it.
        _nonNegativeIfPresent(p, 'actual_duration_min');
        _integerIfPresent(p, 'manual_duration_adjustment_min');
        _intInRange(p, 'manual_actual_set', 0, 1);
        _nullableId(p, 'category_id');
        _nullableId(p, 'recurring_rule_id');
        _nullableId(p, 'rescheduled_from_id');
        _nullableId(p, 'rescheduled_to_id');
        final isInbox = _int(p['is_inbox']) == 1;
        if (isInbox) {
          // Legacy feeds can carry stale schedule fields on explicit Inbox
          // rows. Normalize them before validating the semantic interval.
          p['start_time'] = null;
          p['end_time'] = null;
          p['estimated_duration_min'] = null;
        }
        final start = _dateTime(p['start_time']);
        final end = _dateTime(p['end_time']);
        if (end != null && start == null) {
          throw const SyncValidationException(
            'Task end_time requires start_time',
          );
        }
        if (start != null && end != null && !end.isAfter(start)) {
          throw const SyncValidationException(
            'Task end_time must be later than start_time',
          );
        }
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'categories':
        _requiredText(p, 'name');
        final color = _requiredText(p, 'color_hex');
        if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
          throw const SyncValidationException('Invalid category color');
        }
        _nonNegativeIfPresent(p, 'sort_order');
        _intInRange(p, 'is_focus', 0, 1);
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'subtasks':
        _requiredId(p, 'task_id');
        _requiredText(p, 'title');
        _intInRange(p, 'is_completed', 0, 1);
        _nonNegativeIfPresent(p, 'sort_order');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'tags':
        _requiredText(p, 'name');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'task_tags':
        _requiredId(p, 'task_id');
        _requiredId(p, 'tag_id');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'recurring_rules':
        final rrule = _requiredText(p, 'rrule');
        try {
          RruleUtils.parse(rrule);
        } on Object {
          throw const SyncValidationException('Invalid recurrence rule');
        }
        _requiredText(p, 'task_title');
        _positive(p, 'duration_min');
        _intInRange(p, 'priority', 0, 4);
        _nullableId(p, 'category_id');
        _jsonStringListIfPresent(p, 'tags_json');
        _requiredText(p, 'start_time_of_day');
        if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$')
            .hasMatch(p['start_time_of_day'].toString())) {
          throw const SyncValidationException('Invalid recurrence start time');
        }
        final startDate = _requiredDateOnly(p, 'start_date');
        final endDate = _dateOnlyIfPresent(p, 'end_date');
        if (endDate != null && endDate.isBefore(startDate)) {
          throw const SyncValidationException(
            'Recurrence end_date must not precede start_date',
          );
        }
        _dateOnlyListIfPresent(p, 'exceptions_json');
        _intInRange(p, 'is_active', 0, 1);
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'task_templates':
        _requiredText(p, 'name');
        _positive(p, 'duration_min');
        _intInRange(p, 'priority', 0, 4);
        _nullableId(p, 'category_id');
        _jsonStringListIfPresent(p, 'tags_json');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'daily_reviews':
        _requiredDateOnly(p, 'date');
        _jsonStringListIfPresent(p, 'wins_json');
        _jsonStringListIfPresent(p, 'improvements_json');
        _ratingIfPresent(p, 'energy_level');
        _ratingIfPresent(p, 'productivity_rating');
        _ratingIfPresent(p, 'planning_accuracy_rating');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'weekly_reviews':
        _requiredDateOnly(p, 'week_start_date');
        _jsonStringListIfPresent(p, 'goals_met_json');
        _jsonStringListIfPresent(p, 'goals_missed_json');
        _jsonStringListIfPresent(p, 'next_week_focus_json');
        _ratingIfPresent(p, 'overall_rating');
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'timer_sessions':
        _requiredId(p, 'task_id');
        final started = _requiredDateTime(p, 'started_at');
        final ended = _dateTime(p['ended_at']);
        final duration = _int(p['duration_sec']);
        if (duration == null || duration < 0) {
          throw const SyncValidationException(
            'duration_sec must not be negative',
          );
        }
        if (ended != null && ended.isBefore(started)) {
          throw const SyncValidationException(
            'Timer ended_at must not precede started_at',
          );
        }
        final state = _requiredText(p, 'state');
        if (!TimerSessionState.values
            .map((value) => value.dbValue)
            .contains(state)) {
          throw const SyncValidationException('Invalid timer state');
        }
        final runningSince = _dateTime(p['running_since']);
        if (state == TimerSessionState.running.dbValue) {
          if (ended != null || runningSince == null) {
            throw const SyncValidationException(
              'Running timer must have running_since and no ended_at',
            );
          }
        } else if (state == TimerSessionState.paused.dbValue) {
          if (ended != null || runningSince != null) {
            throw const SyncValidationException(
              'Paused timer cannot have running_since or ended_at',
            );
          }
        } else if (ended == null || runningSince != null) {
          throw const SyncValidationException(
            'Finished timer must have ended_at and no running_since',
          );
        }
        _nullableUuid(p, 'owner_device_id');
        _validateTimerIntervals(p, duration);
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
      case 'day_contexts':
        _requiredDateOnly(p, 'date');
        final dateText = p['date'] as String;
        if (generateDeterministicUuid('day-context:$dateText') !=
            change.recordId) {
          throw const SyncValidationException(
            'Day context ID does not match its calendar date',
          );
        }
        final kind = _requiredText(p, 'kind');
        if (!const {
          'office',
          'holiday',
          'leave',
          'travel',
          'custom',
        }.contains(kind)) {
          throw const SyncValidationException('Invalid day context kind');
        }
        final label = p['custom_label'];
        if (kind == 'custom') {
          if (label is! String ||
              label != label.trim() ||
              label.trim().isEmpty ||
              label.length > 80) {
            throw const SyncValidationException(
              'Custom day context labels must be trimmed and 1–80 characters',
            );
          }
        } else if (label != null) {
          throw const SyncValidationException(
            'Preset day contexts cannot have a custom label',
          );
        }
        _requiredDateTime(p, 'created_at');
        _requiredDateTime(p, 'updated_at');
        break;
    }
  }

  /// Durable pre-v2 operations and historical feed entries did not carry the
  /// state-machine fields. Fill only their structural defaults here. The
  /// database-aware applier additionally protects a current v2 active row
  /// from being downgraded by an old snapshot.
  static void _normalizeLegacyPayload(SyncRemoteChange change) {
    if (change.operation == 'delete') return;
    final payload = change.payload;
    if (change.tableName == 'tasks' &&
        !payload.containsKey('manual_actual_set')) {
      final adjustment = _int(payload['manual_duration_adjustment_min']) ?? 0;
      payload['manual_actual_set'] =
          payload['actual_duration_min'] != null || adjustment != 0 ? 1 : 0;
    }
    if (change.tableName != 'timer_sessions') return;
    final state = payload['state'];
    if (state == null) {
      payload['state'] = payload['ended_at'] == null ? 'running' : 'finished';
    }
    final normalizedState = payload['state']?.toString();
    if (!payload.containsKey('running_since')) {
      payload['running_since'] = normalizedState == 'running'
          ? payload['started_at']
          : null;
    }
    payload.putIfAbsent('work_intervals_json', () => '[]');
    payload.putIfAbsent('owner_device_id', () => null);
  }

  static void _validateIdentity(SyncRemoteChange change) {
    final p = change.payload;
    if (change.tableName == 'task_tags') {
      final parts = change.recordId.split(':');
      if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
        throw const SyncValidationException(
          'Invalid task_tags record identity',
        );
      }
      if (p['task_id'] != null && p['task_id'].toString() != parts[0] ||
          p['tag_id'] != null && p['tag_id'].toString() != parts[1]) {
        throw const SyncValidationException(
          'Record identity does not match payload',
        );
      }
      return;
    }
    if (change.operation == 'delete' && p['deleted'] == true) {
      if (change.recordId.trim().isEmpty) {
        throw const SyncValidationException('Record identity is required');
      }
      return;
    }
    final id = p['id']?.toString();
    if (id == null || id.isEmpty || id != change.recordId) {
      throw const SyncValidationException(
        'Record identity does not match payload',
      );
    }
  }

  static String _requiredText(Map<String, dynamic> p, String key) {
    final raw = p[key];
    final value = raw is String ? raw.trim() : null;
    if (value == null || value.isEmpty) {
      throw SyncValidationException('Missing or blank $key');
    }
    return value;
  }

  static String _requiredId(Map<String, dynamic> p, String key) {
    final value = _requiredText(p, key);
    if (value.length > 200) {
      throw SyncValidationException('$key is too long');
    }
    return value;
  }

  static void _nullableId(Map<String, dynamic> p, String key) {
    final value = p[key];
    if (value != null) _requiredId(p, key);
  }

  static void _nullableUuid(Map<String, dynamic> p, String key) {
    final value = p[key];
    if (value == null) return;
    if (value is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)) {
      throw SyncValidationException('$key must be a UUID');
    }
  }

  static void _validateTimerIntervals(Map<String, dynamic> p, int duration) {
    final raw = p['work_intervals_json'];
    if (raw is! String) {
      throw const SyncValidationException(
        'work_intervals_json must be JSON text',
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const SyncValidationException(
        'work_intervals_json must be valid JSON',
      );
    }
    if (decoded is! List) {
      throw const SyncValidationException(
        'work_intervals_json must be an array',
      );
    }
    DateTime? previousEnd;
    var sum = 0;
    for (final rawInterval in decoded) {
      if (rawInterval is! Map) {
        throw const SyncValidationException('Invalid timer work interval');
      }
      final interval = Map<String, dynamic>.from(rawInterval);
      final start = _requiredDateTime(interval, 'start_at');
      final end = _requiredDateTime(interval, 'end_at');
      final seconds = _int(interval['duration_sec']);
      if (seconds == null ||
          seconds < 0 ||
          end.isBefore(start) ||
          seconds != end.difference(start).inSeconds ||
          (previousEnd != null && start.isBefore(previousEnd))) {
        throw const SyncValidationException('Invalid timer work interval');
      }
      previousEnd = end;
      sum += seconds;
    }
    if (decoded.isNotEmpty && sum != duration) {
      throw const SyncValidationException(
        'Timer work intervals must sum to duration_sec',
      );
    }
  }

  static DateTime _requiredDateTime(Map<String, dynamic> p, String key) {
    final parsed = _dateTime(p[key]);
    if (parsed == null) throw SyncValidationException('Invalid $key');
    return parsed;
  }

  static DateTime _requiredDateOnly(Map<String, dynamic> p, String key) {
    final parsed = _dateOnlyIfPresent(p, key);
    if (parsed == null) throw SyncValidationException('Invalid $key');
    return parsed;
  }

  static DateTime? _dateOnlyIfPresent(Map<String, dynamic> p, String key) {
    final value = p[key];
    if (value == null) return null;
    if (value is! String) {
      throw SyncValidationException('Invalid $key');
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    final parsed = match == null
        ? null
        : DateTime.tryParse('${value}T00:00:00Z');
    if (match == null || parsed == null) {
      throw SyncValidationException('Invalid $key');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw SyncValidationException('Invalid $key');
    }
    return parsed;
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const SyncValidationException('Invalid timestamp');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const SyncValidationException('Invalid timestamp');
    }
    return parsed.toUtc();
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    if (value is String) return int.tryParse(value);
    return null;
  }

  static void _validateOptionalDateTimes(String table, Map<String, dynamic> p) {
    final keys = <String>{'deleted_at'};
    if (table == 'tasks') {
      keys.addAll({'start_time', 'end_time', 'missed_at'});
    } else if (table == 'timer_sessions') {
      keys.add('ended_at');
    }
    for (final key in keys) {
      if (p.containsKey(key)) {
        if (key == 'missed_at') {
          final value = p[key];
          if (value != null &&
              (value is! String || MissedAtCodec.parse(value) == null)) {
            throw const SyncValidationException('Invalid missed_at');
          }
          if (value is String) {
            p[key] = MissedAtCodec.normalize(value);
          }
        } else {
          _dateTime(p[key]);
        }
      }
    }
  }

  static void _jsonStringListIfPresent(Map<String, dynamic> p, String key) {
    final raw = p[key];
    if (raw == null) return;
    if (raw is! String) throw SyncValidationException('$key must be JSON text');
    final decoded = _decodeStringList(raw, key);
    for (final value in decoded) {
      if (value.trim().isEmpty) {
        throw SyncValidationException('$key contains a blank item');
      }
    }
  }

  static void _dateOnlyListIfPresent(Map<String, dynamic> p, String key) {
    final raw = p[key];
    if (raw == null) return;
    if (raw is! String) throw SyncValidationException('$key must be JSON text');
    for (final value in _decodeStringList(raw, key)) {
      final item = <String, dynamic>{key: value};
      _requiredDateOnly(item, key);
    }
  }

  static List<String> _decodeStringList(String raw, String key) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw SyncValidationException('$key must be valid JSON');
    }
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw SyncValidationException('$key must be a JSON array of strings');
    }
    return decoded.cast<String>();
  }

  static void _positive(Map<String, dynamic> p, String key) {
    final value = _int(p[key]);
    if (value == null || value <= 0) {
      throw SyncValidationException('$key must be positive');
    }
  }

  static void _nonNegativeIfPresent(Map<String, dynamic> p, String key) {
    final value = p[key];
    if (value != null && (_int(value) == null || _int(value)! < 0)) {
      throw SyncValidationException('$key must not be negative');
    }
  }

  static void _integerIfPresent(Map<String, dynamic> p, String key) {
    if (p[key] != null && _int(p[key]) == null) {
      throw SyncValidationException('$key must be an integer');
    }
  }

  static void _requiredEnum(
    Map<String, dynamic> p,
    String key,
    Set<String> allowed,
  ) {
    final value = _requiredText(p, key);
    if (!allowed.contains(value)) {
      throw SyncValidationException('$key has an unsupported value');
    }
  }

  static void _intInRange(
    Map<String, dynamic> p,
    String key,
    int min,
    int max,
  ) {
    final value = _int(p[key]);
    if (value == null || value < min || value > max) {
      throw SyncValidationException('$key is outside its allowed range');
    }
  }

  static void _ratingIfPresent(Map<String, dynamic> p, String key) {
    final value = p[key];
    if (value != null) _intInRange(p, key, 1, 5);
  }
}
