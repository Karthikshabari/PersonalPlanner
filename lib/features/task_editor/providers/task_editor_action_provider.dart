import 'package:flutter_riverpod/legacy.dart';

/// Monotonic request counter used by Ctrl+Enter. The editor listens to this
/// provider and performs its normal validated save path, so keyboard saves do
/// not bypass recurrence, tags, timers, or external-change merging.
final taskEditorSaveRequestProvider = StateProvider<int>((ref) => 0);
