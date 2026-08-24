import 'package:flutter_riverpod/legacy.dart';

/// Runtime-only flags (never persisted) marking task blocks that were
/// deliberately left overlapping via the "Keep Overlap" resolution.
/// Rendering also considers blocks that overlap in data, so this set only
/// needs to stay accurate for the current session; it is cleared whenever
/// history changes to avoid stale flags after undo/redo.
final keepOverlapIdsProvider = StateProvider<Set<String>>((ref) => {});
