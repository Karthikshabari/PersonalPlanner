import 'package:freezed_annotation/freezed_annotation.dart';

enum SyncStatus {
  @JsonValue(0)
  synced,
  @JsonValue(1)
  pending,
  @JsonValue(2)
  conflict;

  int get dbValue => index;

  static SyncStatus fromDb(int value) => SyncStatus.values.firstWhere(
      (s) => s.index == value.clamp(0, 2),
      orElse: () => SyncStatus.synced);
}
