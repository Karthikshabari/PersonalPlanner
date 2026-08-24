import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/commands/command_history.dart';
import '../../domain/commands/scheduling_command.dart';

/// Riverpod Notifier exposing the undo/redo stacks (max 50 entries).
final undoStackProvider =
    NotifierProvider<UndoStackNotifier, CommandHistoryState>(
  UndoStackNotifier.new,
);

class UndoStackNotifier extends Notifier<CommandHistoryState> {
  @override
  CommandHistoryState build() => const CommandHistoryState();

  /// Executes [command] and pushes it onto the undo stack (clearing redo).
  Future<void> execute(SchedulingCommand command) async {
    await command.execute();
    state = state.push(command);
  }

  /// Reverts the most recent command. Returns its description, or null when
  /// there is nothing to undo.
  Future<String?> undo() async {
    if (!state.canUndo) return null;
    final command = state.lastCommand!;
    await command.undo();
    state = state.popUndo();
    return command.description;
  }

  /// Re-executes the most recently undone command. Returns its description,
  /// or null when there is nothing to redo.
  Future<String?> redo() async {
    if (!state.canRedo) return null;
    final command = state.redoStack.last;
    await command.execute();
    state = state.popRedo();
    return command.description;
  }
}
