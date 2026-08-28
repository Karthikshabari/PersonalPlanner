import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rrule/rrule.dart';

import '../../../recurring/domain/rrule_utils.dart';
import 'custom_recurrence_dialog.dart';

/// "Repeat" dropdown in the task editor: Never / Daily / Weekdays / Weekly /
/// Monthly / Custom (planner.md Chunk 4 #5). Presets generate the RRULE
/// string; Custom opens [showCustomRecurrenceDialog].
class RecurrencePicker extends ConsumerWidget {
  final RepeatPreset selection;
  /// Set when the user confirmed the custom dialog.
  final CustomRecurrenceConfig? customConfig;
  /// Rule currently attached to the edited task, if any — used as anchor for
  /// presets and to detect whether "Never" detaches an existing rule.
  final String? existingRrule;
  final DateTime anchorDate;
  final ValueChanged<RepeatPreset> onChanged;
  final ValueChanged<CustomRecurrenceConfig> onCustomConfirmed;

  const RecurrencePicker({
    super.key,
    required this.selection,
    required this.anchorDate,
    required this.onChanged,
    required this.onCustomConfirmed,
    this.customConfig,
    this.existingRrule,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<RepeatPreset>(
      key: const ValueKey('recurrence-picker'),
      initialValue: selection,
      decoration:
          const InputDecoration(labelText: 'Repeat'),
      isExpanded: true,
      items: [
        for (final preset in RepeatPreset.values)
          DropdownMenuItem(
            value: preset,
            child: Text(_labelFor(context, preset)),
          ),
      ],
      onChanged: (preset) async {
        if (preset == null) return;
        if (preset == RepeatPreset.custom) {
          final config = await showCustomRecurrenceDialog(
            context,
            anchorDate: anchorDate,
            initial: customConfig ??
                _configFromPreset(selection, anchorDate, existingRrule),
          );
          if (config == null) {
            // Dialog cancelled: keep the previous selection unless it was
            // already Custom without a config.
            if (selection != RepeatPreset.custom) return;
            onChanged(RepeatPreset.never);
            return;
          }
          onCustomConfirmed(config);
          return;
        }
        onChanged(preset);
      },
    );
  }

  String _labelFor(BuildContext context, RepeatPreset preset) {
    if (preset == RepeatPreset.custom) {
      if (customConfig != null || existingRrule != null) return 'Custom (edited)';
    }
    return switch (preset) {
      RepeatPreset.never => 'Never',
      RepeatPreset.daily => 'Daily',
      RepeatPreset.weekdays => 'Weekdays',
      RepeatPreset.weekly => 'Weekly',
      RepeatPreset.monthly => 'Monthly',
      RepeatPreset.custom => 'Custom…',
    };
  }
}

CustomRecurrenceConfig _configFromPreset(
  RepeatPreset preset,
  DateTime anchorDate,
  String? existingRrule,
) {
  if (existingRrule != null) {
    try {
      final rule = RruleUtils.parse(existingRrule);
      return CustomRecurrenceConfig(
        frequency: rule.frequency,
        interval: rule.actualInterval,
        byWeekDays: rule.byWeekDays.map((e) => e.day).toSet(),
        endDate: null,
      );
    } catch (_) {}
  }
  return switch (preset) {
    RepeatPreset.daily =>
      const CustomRecurrenceConfig(frequency: Frequency.daily),
    RepeatPreset.weekly =>
      const CustomRecurrenceConfig(frequency: Frequency.weekly),
    RepeatPreset.monthly =>
      const CustomRecurrenceConfig(frequency: Frequency.monthly),
    _ => const CustomRecurrenceConfig(frequency: Frequency.weekly),
  };
}
