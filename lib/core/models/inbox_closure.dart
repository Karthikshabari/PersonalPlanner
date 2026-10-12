// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_closure.freezed.dart';
part 'inbox_closure.g.dart';

/// How an Inbox idea left the open lists.
@JsonEnum(valueField: 'dbValue')
enum InboxCloseKind {
  closed('closed'),
  letGo('let_go'),
  experiment('experiment');

  const InboxCloseKind(this.dbValue);
  final String dbValue;
}

/// One close / let go / experiment event on an Inbox idea, with the Bring back
/// that reversed it (if any). The history is append-only: Bring back sets
/// [reopenedAt] on the last event and never removes it, so reasons stay
/// readable. Snake_case keys keep the stored, backed-up and synced value
/// portable.
@freezed
abstract class InboxClosure with _$InboxClosure {
  const factory InboxClosure({
    required InboxCloseKind kind,

    /// UTC instant the item was closed.
    required DateTime at,

    /// Trimmed, 1..200 code points. Required for closed, optional for let go,
    /// absent for experiment.
    String? reason,

    /// `experiment:<tagId>` id; only for kind experiment.
    @JsonKey(name: 'experiment_id') String? experimentId,

    /// UTC instant of Bring back; null while closed. Only the last event may
    /// be null.
    @JsonKey(name: 'reopened_at') DateTime? reopenedAt,
  }) = _InboxClosure;

  factory InboxClosure.fromJson(Map<String, dynamic> json) =>
      _$InboxClosureFromJson(json);
}
