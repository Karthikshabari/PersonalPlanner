import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tags_table.dart';

part 'tag_dao.g.dart';

@DriftAccessor(tables: [Tags, TaskTags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  Stream<List<TagRow>> watchActiveTags() {
    return (select(tags)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<TagRow?> getTagById(String id) =>
      (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<TagRow?> getTagByName(String name) =>
      (select(tags)
            ..where((t) => t.name.equals(name))
            ..orderBy([(t) => OrderingTerm.asc(t.deletedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> insertTag(TagsCompanion entry) =>
      into(tags).insert(entry, mode: InsertMode.insertOrIgnore);

  Future<bool> updateTag(TagRow row) async {
    final count = await (update(tags)..where((tag) => tag.id.equals(row.id)))
        .write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  Future<void> softDeleteTag(String id, DateTime deletedAt) {
    final now = deletedAt.toUtc();
    return transaction(() async {
      final current = await getTagById(id);
      if (current == null || current.deletedAt != null) return;
      await updateTag(
        current.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          syncStatus: 1,
          revision: current.revision + 1,
        ),
      );
      // Detach the tag from every task.
      await customUpdate(
        'UPDATE task_tags SET deleted_at = ?, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE tag_id = ? AND deleted_at IS NULL',
        variables: [
          Variable<String>(now.toIso8601String()),
          Variable<String>(now.toIso8601String()),
          Variable<String>(id),
        ],
        updates: {taskTags},
      );
    });
  }

  Stream<List<TagRow>> watchTagsForTask(String taskId) {
    final query =
        select(tags)
            .join([innerJoin(taskTags, taskTags.tagId.equalsExp(tags.id))])
          ..where(
            tags.deletedAt.isNull() &
                taskTags.deletedAt.isNull() &
                taskTags.taskId.equals(taskId),
          )
          ..orderBy([OrderingTerm.asc(tags.name)]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(tags)).toList(),
    );
  }

  Future<void> linkTaskTag(String taskId, String tagId, DateTime createdAt) {
    final now = createdAt.toUtc();
    return transaction(() async {
      final existing =
          await (select(taskTags)..where(
                (tt) => tt.taskId.equals(taskId) & tt.tagId.equals(tagId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await into(taskTags).insert(
          TaskTagsCompanion.insert(
            taskId: taskId,
            tagId: tagId,
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value(1),
            revision: const Value(1),
          ),
        );
      } else if (existing.deletedAt != null) {
        await (update(
              taskTags,
            )..where((tt) => tt.taskId.equals(taskId) & tt.tagId.equals(tagId)))
            .write(
              TaskTagsCompanion(
                updatedAt: Value(now),
                deletedAt: const Value(null),
                syncStatus: const Value(1),
                revision: Value(existing.revision + 1),
              ),
            );
      }
    });
  }

  Future<int> unlinkTaskTag(String taskId, String tagId) async {
    final existing =
        await (select(
              taskTags,
            )..where((tt) => tt.taskId.equals(taskId) & tt.tagId.equals(tagId)))
            .getSingleOrNull();
    if (existing == null || existing.deletedAt != null) return 0;
    final now = DateTime.now().toUtc();
    return (update(
      taskTags,
    )..where((tt) => tt.taskId.equals(taskId) & tt.tagId.equals(tagId))).write(
      TaskTagsCompanion(
        updatedAt: Value(now),
        deletedAt: Value(now),
        syncStatus: const Value(1),
        revision: Value(existing.revision + 1),
      ),
    );
  }
}
