import 'package:freezed_annotation/freezed_annotation.dart';

part 'timer_session.freezed.dart';
part 'timer_session.g.dart';

/// One start→pause span on a task (planner.md Chunk 6 #2). `endedAt == null`
/// means the session is currently running.
@freezed
abstract class TimerSession with _$TimerSession {
  const factory TimerSession({
    required String id,
    required String taskId,
    required DateTime startedAt,
    DateTime? endedAt,
    @Default(0) int durationSec,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _TimerSession;

  factory TimerSession.fromJson(Map<String, dynamic> json) =>
      _$TimerSessionFromJson(json);
}
