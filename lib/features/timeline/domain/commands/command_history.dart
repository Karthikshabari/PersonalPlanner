import 'scheduling_command.dart';

/// Immutable snapshot of the undo/redo stacks.
class CommandHistoryState {
  static const int maxUndoEntries = 50;

  final List<SchedulingCommand> undoStack;
  final List<SchedulingCommand> redoStack;

  const CommandHistoryState({
    this.undoStack = const [],
    this.redoStack = const [],
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  SchedulingCommand? get lastCommand =>
      undoStack.isEmpty ? null : undoStack.last;

  CommandHistoryState push(SchedulingCommand command) {
    final nextUndo = [...undoStack, command];
    if (nextUndo.length > maxUndoEntries) {
      nextUndo.removeRange(0, nextUndo.length - maxUndoEntries);
    }
    // A new command invalidates the redo branch.
    return CommandHistoryState(undoStack: nextUndo, redoStack: const []);
  }

  CommandHistoryState popUndo() {
    if (undoStack.isEmpty) return this;
    return CommandHistoryState(
      undoStack: [...undoStack]..removeLast(),
      redoStack: [...redoStack, undoStack.last],
    );
  }

  CommandHistoryState popRedo() {
    if (redoStack.isEmpty) return this;
    return CommandHistoryState(
      undoStack: [...undoStack, redoStack.last],
      redoStack: [...redoStack]..removeLast(),
    );
  }
}
