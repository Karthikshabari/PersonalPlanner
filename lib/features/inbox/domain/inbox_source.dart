import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/models/experiment.dart';
import 'inbox_status.dart';

part 'inbox_source.freezed.dart';

/// The few columns of an experiment an Inbox chip needs.
@freezed
abstract class InboxExperimentFacts with _$InboxExperimentFacts {
  const factory InboxExperimentFacts({
    required String id,
    required String name,
    required String startDate,
    required String endDate,
    required ExperimentStatus status,
    ExperimentOutcome? outcome,
    String? concludedOn,
    DateTime? retiredAt,
    DateTime? deletedAt,
  }) = _InboxExperimentFacts;
}

/// Everything the Inbox board is derived from, read with four light queries.
/// Deep equality, so an unchanged read does not rebuild the screen.
@freezed
abstract class InboxSource with _$InboxSource {
  const factory InboxSource({
    /// Open and closed ideas (`is_inbox = 1`, not deleted).
    @Default(<InboxItemFacts>[]) List<InboxItemFacts> items,

    /// Every row with an `inbox_item_id`, deleted ones included.
    @Default(<InboxSessionFacts>[]) List<InboxSessionFacts> sessions,

    /// Saved Review reasons (trimmed, non-blank) by session id. Read from
    /// `daily_reviews.task_reasons_json` for the planner date of each session
    /// that is not done. Unsaved drafts are not here.
    @Default(<String, String>{}) Map<String, String> reasons,

    /// Experiments named in an idea's history, by id. A missing key means the
    /// experiment row is gone.
    @Default(<String, InboxExperimentFacts>{})
    Map<String, InboxExperimentFacts> experiments,
  }) = _InboxSource;
}
