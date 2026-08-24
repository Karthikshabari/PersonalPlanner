import 'scheduling_command.dart';

/// Groups multiple commands into one reversible unit.
/// execute: run children in order; undo: run all undo() in REVERSE order.
class BatchCommand implements SchedulingCommand {
  final List<SchedulingCommand> commands;

  BatchCommand(this.commands);

  @override
  String get description => commands.isEmpty
      ? 'Batch operation'
      : '${commands.first.description} (+${commands.length - 1} more)';

  @override
  Future<void> execute() async {
    for (final command in commands) {
      await command.execute();
    }
  }

  @override
  Future<void> undo() async {
    for (final command in commands.reversed) {
      await command.undo();
    }
  }
}
