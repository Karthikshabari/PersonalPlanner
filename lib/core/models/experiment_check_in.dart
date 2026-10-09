import 'package:freezed_annotation/freezed_annotation.dart';

part 'experiment_check_in.freezed.dart';

/// A short written note about how an experiment is going, one per slot date.
@freezed
abstract class ExperimentCheckIn with _$ExperimentCheckIn {
  const factory ExperimentCheckIn({
    required String id,
    required String experimentId,
    required String slotDate,
    required String note,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ExperimentCheckIn;
}
