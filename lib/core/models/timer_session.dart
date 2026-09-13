// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'timer_session.freezed.dart';
part 'timer_session.g.dart';

enum TimerSessionState {
  @JsonValue('running')
  running,
  @JsonValue('paused')
  paused,
  @JsonValue('finished')
  finished;

  String get dbValue => name;

  static TimerSessionState fromDb(String value) =>
      TimerSessionState.values.firstWhere((state) => state.dbValue == value);
}

/// One closed, measured part of a logical timer session. Paused wall time is
/// intentionally absent from this source of truth.
@freezed
abstract class TimerWorkInterval with _$TimerWorkInterval {
  const factory TimerWorkInterval({
    @JsonKey(name: 'start_at') required DateTime startAt,
    @JsonKey(name: 'end_at') required DateTime endAt,
    @JsonKey(name: 'duration_sec') required int durationSec,
  }) = _TimerWorkInterval;

  factory TimerWorkInterval.fromJson(Map<String, dynamic> json) =>
      _$TimerWorkIntervalFromJson(json);
}

/// One logical timer session. Closed work segments are retained through every
/// pause/resume; only a finished session contributes to Actual Duration.
@freezed
abstract class TimerSession with _$TimerSession {
  const factory TimerSession({
    required String id,
    required String taskId,
    required DateTime startedAt,
    DateTime? endedAt,
    @Default(0) int durationSec,
    @Default(TimerSessionState.finished) TimerSessionState state,
    DateTime? runningSince,
    @Default(<TimerWorkInterval>[]) List<TimerWorkInterval> workIntervals,
    String? ownerDeviceId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _TimerSession;

  factory TimerSession.fromJson(Map<String, dynamic> json) =>
      _$TimerSessionFromJson(json);
}
