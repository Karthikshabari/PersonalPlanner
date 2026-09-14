import '../../../../core/models/enums/priority.dart';
import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

/// Reversible priority change used by the desktop number-key shortcuts.
class ChangePriorityCommand implements SchedulingCommand {
  final TaskRepository repository;
  final Task original;
  final Priority newPriority;

  ChangePriorityCommand({
    required this.repository,
    required this.original,
    required this.newPriority,
  });

  @override
  String get description => 'Set priority for "${original.title}"';

  Future<void> _apply(Priority priority) async {
    final current = await repository.getTaskById(original.id);
    if (current == null) return;
    await repository.updateTask(current.copyWith(priority: priority));
  }

  @override
  Future<void> execute() => _apply(newPriority);

  @override
  Future<void> undo() => _apply(original.priority);
}
