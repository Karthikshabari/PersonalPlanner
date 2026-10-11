import '../../../core/models/day_context.dart';
import 'day_context_presets.dart';

/// The one rule for break days. A day is a break when its context label is
/// the name of a preset whose Break day switch is on (case and spaces
/// ignored). The label is looked up at read time, so a renamed or deleted
/// preset leaves its days with their old label, and those days are breaks
/// only while some preset with that label still has the switch on. An old
/// custom label matches no preset and is never a break.
///
/// Equal when the same names are breaks, so renaming a preset that changes no
/// break day does not recalculate anything.
class BreakDayRule {
  BreakDayRule(Iterable<DayContextPreset> presets)
    : _breakNames = {
        for (final preset in presets)
          if (preset.isBreak) DayContextPresets.normalize(preset.name),
      };

  final Set<String> _breakNames;

  static final defaults = BreakDayRule(defaultDayContextPresets);

  /// The day's label when [context] makes it a break day, else null.
  String? breakLabel(DayContext? context) {
    if (context == null || context.deletedAt != null) return null;
    final label = context.label;
    return _breakNames.contains(DayContextPresets.normalize(label))
        ? label
        : null;
  }

  bool isBreakDay(DayContext? context) => breakLabel(context) != null;

  /// `yyyy-MM-dd` → label for the break days among [contexts].
  Map<String, String> breakDates(Iterable<DayContext> contexts) => {
    for (final context in contexts) context.date: ?breakLabel(context),
  };

  @override
  bool operator ==(Object other) =>
      other is BreakDayRule &&
      other._breakNames.length == _breakNames.length &&
      other._breakNames.containsAll(_breakNames);

  @override
  int get hashCode => Object.hashAllUnordered(_breakNames);
}
