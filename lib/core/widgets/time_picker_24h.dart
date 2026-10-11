import 'package:flutter/material.dart';

/// [showTimePicker] in 24-hour form (no AM/PM), matching the timeline's
/// "13:00" labels. There is no time-format setting.
Future<TimeOfDay?> showTimePicker24h({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}
