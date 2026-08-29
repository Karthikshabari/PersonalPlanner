import '../../../../core/models/enums/task_status.dart';
import '../../../../core/models/task.dart';
import '../../data/task_repository.dart';
import 'scheduling_command.dart';

class ChangeStatusCommand implements SchedulingCommand {
  final TaskRepository repository;
  final String taskId;
  final TaskStatus newStatus;
  Task? _before;

  ChangeStatusCommand({
    required this.repository,
    required this.taskId,
    required this.newStatus,
  });

  @override
  String get description => 'Change task status';

  @override
  Future<void> execute() async {
    final current = await repository.getTaskById(taskId);
    if (current == null || current.deletedAt != null) {
      throw StateError('Task $taskId not found');
    }
    if (!current.status.allowedTransitions.contains(newStatus)) {
      throw StateError(
        'Cannot change ${current.status.label} to ${newStatus.label}',
      );
    }
    _before = current;
    await repository.updateTask(current.copyWith(status: newStatus));
  }

  @override
  Future<void> undo() async {
    final before = _before;
    if (before == null) return;
    final current = await repository.getTaskById(taskId);
    if (current == null) return;
    await repository.updateTask(
      current.copyWith(status: before.status),
      allowStatusTransition: true,
    );
  }
}
