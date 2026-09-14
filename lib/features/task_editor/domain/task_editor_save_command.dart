import '../../../core/database/app_database.dart';

/// Runs every persistence side of one editor Save in the same Drift
/// transaction. Repositories may open nested transactions; Drift keeps those
/// writes inside this outer transaction so a late tag/timer/rule failure rolls
/// the task update back as well.
class TaskEditorSaveCommand {
  TaskEditorSaveCommand(this.database);

  final AppDatabase database;

  Future<T> execute<T>(Future<T> Function() mutation) =>
      database.transaction(mutation);
}
