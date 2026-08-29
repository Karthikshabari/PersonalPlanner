import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/task_templates_table.dart';

part 'template_dao.g.dart';

@DriftAccessor(tables: [TaskTemplates])
class TemplateDao extends DatabaseAccessor<AppDatabase>
    with _$TemplateDaoMixin {
  TemplateDao(super.db);

  Stream<List<TaskTemplateRow>> watchActiveTemplates() {
    return (select(taskTemplates)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<TaskTemplateRow>> getActiveTemplates() =>
      (select(taskTemplates)..where((t) => t.deletedAt.isNull())).get();

  Future<TaskTemplateRow?> getTemplateById(String id) =>
      (select(taskTemplates)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertTemplate(TaskTemplatesCompanion entry) =>
      into(taskTemplates).insert(entry);

  Future<bool> updateTemplate(TaskTemplateRow row) async {
    final count =
        await (update(
          taskTemplates,
        )..where((template) => template.id.equals(row.id))).write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  Future<int> softDeleteTemplate(String id, DateTime deletedAt) async {
    final current = await getTemplateById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(taskTemplates)..where((t) => t.id.equals(id))).write(
      TaskTemplatesCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }
}
