import 'dart:convert';

import '../../../core/utils/missed_at.dart';

/// Keys that never carry user intent. Snapshots differing only here describe
/// the same record state.
const Set<String> nonSemanticSyncKeys = {
  'created_at',
  'updated_at',
  'server_version',
  'user_id',
  'change_id',
  'server_timestamp',
  '_planner_payload_version',
  '_planner_revision',
  'sync_status',
  'revision',
  'actual_duration_min',
  'estimated_duration_min',
};

const Map<String, Set<String>> _instantKeys = {
  'tasks': {'start_time', 'end_time'},
  'timer_sessions': {'started_at', 'ended_at', 'running_since'},
};

const Set<String> _jsonTextKeys = {
  'plan_title_history_json',
  'work_intervals_json',
  'tags_json',
  'exceptions_json',
  'wins_json',
  'improvements_json',
  'goals_met_json',
  'goals_missed_json',
  'next_week_focus_json',
};

/// True when [local] and [remote] describe the same state of one [table] row.
/// A remote `{deleted: true}` absence marker is never equal to anything.
bool semanticallyEqualSnapshots(
  String table,
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
) {
  if (remote['deleted'] == true || local['deleted'] == true) return false;
  final keys = {...local.keys, ...remote.keys}..removeAll(nonSemanticSyncKeys);
  for (final key in keys) {
    if (!_sameValue(table, key, local[key], remote[key])) return false;
  }
  return true;
}

bool _sameValue(String table, String key, Object? a, Object? b) {
  if (key == 'deleted_at') return (a == null) == (b == null);
  if (a == null || b == null) return a == null && b == null;
  if (key == 'missed_at') {
    return MissedAtCodec.normalize('$a') == MissedAtCodec.normalize('$b');
  }
  if (_instantKeys[table]?.contains(key) ?? false) {
    final left = DateTime.tryParse('$a');
    final right = DateTime.tryParse('$b');
    return left != null && right != null && left.isAtSameMomentAs(right);
  }
  if (_jsonTextKeys.contains(key)) return _jsonEqual(a, b);
  return _scalar(a) == _scalar(b);
}

Object _scalar(Object value) {
  if (value is bool) return value ? 1 : 0;
  if (value is double && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value is num ? value : '$value';
}

bool _jsonEqual(Object a, Object b) {
  Object? decode(Object value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }

  return jsonEncode(_canonical(decode(a))) == jsonEncode(_canonical(decode(b)));
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
