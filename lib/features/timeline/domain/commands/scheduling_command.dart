/// Base class for reversible scheduling operations (architecture.md §8).
/// Every command captures everything needed to apply and revert itself.
abstract class SchedulingCommand {
  /// Human-readable label used for undo/redo toast feedback.
  String get description;

  Future<void> execute();

  Future<void> undo();
}

/// Optional result marker for commands whose exact retry may be a no-op.
abstract interface class MutationAwareSchedulingCommand {
  bool get didMutate;
}
