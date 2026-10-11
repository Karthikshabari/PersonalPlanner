import 'analytics_models.dart';

const String followThroughTargetSettingKey = 'insights_follow_through_target';

/// Stored as whole percent text (`"60"`). Absent or anything other than one of
/// [followThroughTargetChoices] yields [defaultFollowThroughTarget].
double decodeFollowThroughTarget(String? raw) {
  final percent = int.tryParse(raw?.trim() ?? '');
  for (final choice in followThroughTargetChoices) {
    if (percent == followThroughTargetPercent(choice)) return choice;
  }
  return defaultFollowThroughTarget;
}

String encodeFollowThroughTarget(double target) =>
    '${followThroughTargetPercent(target)}';

int followThroughTargetPercent(double target) => (target * 100).round();
