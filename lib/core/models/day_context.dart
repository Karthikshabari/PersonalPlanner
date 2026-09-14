import 'package:freezed_annotation/freezed_annotation.dart';

part 'day_context.freezed.dart';
part 'day_context.g.dart';

enum DayContextKind {
  @JsonValue('office')
  office,
  @JsonValue('holiday')
  holiday,
  @JsonValue('leave')
  leave,
  @JsonValue('travel')
  travel,
  @JsonValue('custom')
  custom;

  String get dbValue => name;

  static DayContextKind fromDb(String value) =>
      DayContextKind.values.firstWhere((kind) => kind.dbValue == value);

  String get label => switch (this) {
    DayContextKind.office => 'Office Day',
    DayContextKind.holiday => 'Holiday / Festival',
    DayContextKind.leave => 'Leave',
    DayContextKind.travel => 'Travel',
    DayContextKind.custom => 'Custom',
  };

  String get shortLabel => switch (this) {
    DayContextKind.office => 'Office',
    DayContextKind.holiday => 'Holiday',
    DayContextKind.leave => 'Leave',
    DayContextKind.travel => 'Travel',
    DayContextKind.custom => 'Custom',
  };

  String get semanticsLabel => switch (this) {
    DayContextKind.office => 'Office day',
    DayContextKind.holiday => 'Holiday or festival',
    DayContextKind.leave => 'Leave',
    DayContextKind.travel => 'Travel',
    DayContextKind.custom => 'Custom day context',
  };
}

@freezed
abstract class DayContext with _$DayContext {
  const factory DayContext({
    required String id,
    required String date,
    required DayContextKind kind,
    String? customLabel,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    @Default(1) int revision,
  }) = _DayContext;

  factory DayContext.fromJson(Map<String, dynamic> json) =>
      _$DayContextFromJson(json);
}

extension DayContextX on DayContext {
  String get displayLabel =>
      kind == DayContextKind.custom ? customLabel! : kind.shortLabel;
}
