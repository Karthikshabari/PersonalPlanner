import '../../../../core/database/app_database.dart';
import 'scheduling_command.dart';

/// Groups multiple commands into one reversible unit.
/// execute: run children in order; undo: run all undo() in REVERSE order.
class BatchCommand
    implements SchedulingCommand, MutationAwareSchedulingCommand {
  final List<SchedulingCommand> commands;
  final AppDatabase? database;
  final Future<void> Function()? beforeExecute;

  BatchCommand(
    this.commands, {
    this.database,
    this.beforeExecute,
  });

  @override
  bool get didMutate => commands.any(
    (command) => command is! MutationAwareSchedulingCommand ||
        (command as MutationAwareSchedulingCommand).didMutate,
  );

  @override
  String get description => commands.isEmpty
      ? 'Batch operation'
      : '${commands.first.description} (+${commands.length - 1} more)';

  @override
  Future<void> execute() {
    Future<void> run() async {
      await beforeExecute?.call();
      for (final command in commands) {
        await command.execute();
      }
    }

    return database == null ? run() : database!.transaction(run);
  }

  @override
  Future<void> undo() {
    Future<void> run() async {
      for (final command in commands.reversed) {
        await command.undo();
      }
    }

    return database == null ? run() : database!.transaction(run);
  }
}
