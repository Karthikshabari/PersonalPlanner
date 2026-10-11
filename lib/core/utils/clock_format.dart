/// 24-hour `HH:mm` text for an instant that is already in the zone to show
/// (the caller converts, for example with `PlannerTimeZone.toPlannerLocal`).
String formatClock24(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';
