import 'package:flutter/material.dart';

import '../../../core/models/day_context.dart';

/// Same mapping as the Day header's context action (D22).
IconData dayContextIcon(DayContextKind kind) => switch (kind) {
  DayContextKind.office => Icons.business_outlined,
  DayContextKind.holiday => Icons.celebration_outlined,
  DayContextKind.leave => Icons.event_busy_outlined,
  DayContextKind.travel => Icons.luggage_outlined,
  DayContextKind.custom => Icons.label_outline,
};
