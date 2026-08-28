import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/template_dao.dart';
import '../../../core/models/task_template.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/uuid.dart';

/// CRUD for task templates (planner.md Chunk 4 #10).
class TemplateRepository {
  final AppDatabase _db;

  TemplateRepository(this._db);

  TemplateDao get _dao => _db.templateDao;

  Future<TaskTemplate> insertTemplate(TaskTemplate template) async {
    final now = DateTime.now();
    final effective = template.copyWith(
      id: template.id.isEmpty ? generateUuidV7() : template.id,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.insertTemplate(_toCompanion(effective));
    return effective;
  }

  Future<TaskTemplate> updateTemplate(TaskTemplate template) async {
    final row = await _dao.getTemplateById(template.id);
    if (row == null) throw StateError('Template ${template.id} not found');
    final effective = template.copyWith(updatedAt: DateTime.now());
    await _dao.updateTemplate(
        _toRow(effective, syncStatus: row.syncStatus, revision: row.revision));
    return effective;
  }

  Future<void> deleteTemplate(String templateId) =>
      _dao.softDeleteTemplate(templateId, DateTime.now());

  Stream<List<TaskTemplate>> watchAllTemplates() => _dao
      .watchActiveTemplates()
      .map((rows) => rows.map(fromRow).toList(growable: false));

  Future<List<TaskTemplate>> getAllTemplates() async =>
      (await _dao.getActiveTemplates()).map(fromRow).toList();

  Future<TaskTemplate?> getTemplateById(String templateId) async {
    final row = await _dao.getTemplateById(templateId);
    return row == null ? null : fromRow(row);
  }

  static TaskTemplate fromRow(TaskTemplateRow row) => TaskTemplate(
        id: row.id,
        name: row.name,
        description: row.description,
        durationMin: row.durationMin,
        categoryId: row.categoryId,
        priority: row.priority,
        tags: JsonListUtils.decode(row.tagsJson),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  static TaskTemplatesCompanion _toCompanion(TaskTemplate t) =>
      TaskTemplatesCompanion.insert(
        id: t.id,
        name: t.name,
        description: Value(t.description),
        durationMin: t.durationMin,
        categoryId: Value(t.categoryId),
        priority: Value(t.priority),
        tagsJson: Value(
            t.tags.isEmpty ? null : JsonListUtils.encode(t.tags)),
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: Value(t.deletedAt),
      );

  static TaskTemplateRow _toRow(
    TaskTemplate t, {
    required int syncStatus,
    required int revision,
  }) =>
      TaskTemplateRow(
        id: t.id,
        name: t.name,
        description: t.description,
        durationMin: t.durationMin,
        categoryId: t.categoryId,
        priority: t.priority,
        tagsJson: t.tags.isEmpty ? null : JsonListUtils.encode(t.tags),
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: t.deletedAt,
        syncStatus: syncStatus,
        revision: revision,
      );
}
