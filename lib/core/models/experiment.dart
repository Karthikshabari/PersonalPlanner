// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'experiment.freezed.dart';
part 'experiment.g.dart';

enum ExperimentStatus {
  running('running'),
  concluded('concluded');

  const ExperimentStatus(this.dbValue);

  final String dbValue;

  static ExperimentStatus fromDb(String value) => ExperimentStatus.values
      .firstWhere((s) => s.dbValue == value, orElse: () => running);
}

enum ExperimentOutcome {
  continueHabit('continue_habit', 'Continue as a habit'),
  drop('drop', 'Drop it');

  const ExperimentOutcome(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ExperimentOutcome? fromDb(String? value) {
    if (value == null) return null;
    for (final outcome in values) {
      if (outcome.dbValue == value) return outcome;
    }
    return null;
  }
}

/// The check-in frequencies an experiment may use, in days (ED9).
const experimentCheckInFrequencies = [1, 3, 7, 10, 15];

/// One entry of the extension history (`experiments.extensions_json`, ED8).
/// All values are text; dates are `yyyy-MM-dd`.
@freezed
abstract class ExperimentExtension with _$ExperimentExtension {
  const factory ExperimentExtension({
    required String reason,
    @JsonKey(name: 'previous_end_date') required String previousEndDate,
    @JsonKey(name: 'new_end_date') required String newEndDate,
    @JsonKey(name: 'made_on') required String madeOn,
  }) = _ExperimentExtension;

  factory ExperimentExtension.fromJson(Map<String, dynamic> json) =>
      _$ExperimentExtensionFromJson(json);
}

/// A time-boxed trial linked to exactly one tag. Dates are `yyyy-MM-dd`.
@freezed
abstract class Experiment with _$Experiment {
  const factory Experiment({
    required String id,
    required String tagId,
    required String tagName,
    String? purpose,
    required String startDate,
    required String endDate,
    required int weekdayTargetMin,
    required int weekendTargetMin,
    required int checkInEveryDays,
    required ExperimentStatus status,
    @Default(<ExperimentExtension>[]) List<ExperimentExtension> extensions,
    ExperimentOutcome? outcome,
    String? conclusionNote,
    String? concludedOn,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(1) int revision,
  }) = _Experiment;
}
