import 'package:flutter_riverpod/legacy.dart';

/// A one-shot request shared by the app-level shortcut layer and the mounted
/// timeline. Keeping the request in Riverpod lets a shortcut opened from a
/// different route navigate to Day View without reaching into widget state.
final timelineQuickCreateSlotProvider = StateProvider<int?>((ref) => null);

/// Incremented when Escape asks the timeline to cancel a live move/resize.
final timelineCancelRequestProvider = StateProvider<int>((ref) => 0);
