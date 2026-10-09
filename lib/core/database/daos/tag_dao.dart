import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/tags_table.dart';

part 'tag_dao.g.dart';

/// An active tag as offered by the editor's tag field.
class TagOptionRow {
  const TagOptionRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.hasExperiment,
  });

  final String id;
  final String name;

  /// Creation instant as stored (UTC ISO text); only used to order tags that
  /// share a name key.
  final String createdAt;

  /// True when an experiment is linked to this tag.
  final bool hasExperiment;
}

/// How many blocks carry a tag, and when the earliest one starts.
class TagUsageRow {
  const TagUsageRow({required this.blockCount, required this.firstStart});

  final int blockCount;

  /// Start instant of the earliest block, or null when there is none.
  final DateTime? firstStart;
}

/// ED18: the message shared by every deletion path.
String experimentTagRemovalMessage(String tagId) =>
    'Tag $tagId belongs to an experiment and cannot be removed';

@DriftAccessor(tables: [Tags, TaskTags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  Stream<List<TagRow>> watchActiveTags() {
    return (select(tags)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Active tags, earliest created first, then smallest id.
  Future<List<TagRow>> getActiveTags() =>
      (select(tags)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

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

  /// Active tags with a flag telling whether an experiment uses them,
  /// ordered by name. Reads `experiments` too, so the stream fires when an
  /// experiment is created.
  Stream<List<TagOptionRow>> watchTagOptions() {
    return customSelect(
      'SELECT t.id AS id, t.name AS name, t.created_at AS created_at, '
      'EXISTS (SELECT 1 FROM experiments e WHERE e.tag_id = t.id) '
      'AS has_experiment '
      'FROM tags t WHERE t.deleted_at IS NULL ORDER BY t.name',
      readsFrom: {tags, attachedDatabase.experiments},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          TagOptionRow(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            createdAt: row.read<String>('created_at'),
            hasExperiment: row.read<int>('has_experiment') != 0,
          ),
      ],
    );
  }

  /// One aggregate over the non-deleted, non-Inbox tasks that carry [tagId].
  Future<TagUsageRow> getTagUsage(String tagId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS block_count, MIN(start_time) AS first_start '
      'FROM tasks WHERE tag_id = ? AND deleted_at IS NULL AND is_inbox = 0',
      variables: [Variable<String>(tagId)],
      readsFrom: {attachedDatabase.tasks},
    ).getSingle();
    final first = row.readNullable<String>('first_start');
    return TagUsageRow(
      blockCount: row.read<int>('block_count'),
      firstStart: first == null ? null : DateTime.parse(first),
    );
  }

  /// True when any experiment row references [tagId].
  Future<bool> tagBelongsToExperiment(String tagId) async {
    final row = await customSelect(
      'SELECT EXISTS (SELECT 1 FROM experiments WHERE tag_id = ?) AS used',
      variables: [Variable<String>(tagId)],
      readsFrom: {attachedDatabase.experiments},
    ).getSingle();
    return row.read<int>('used') != 0;
  }

  Future<void> softDeleteTag(String id, DateTime deletedAt) {
    final now = deletedAt.toUtc();
    return transaction(() async {
      final current = await getTagById(id);
      if (current == null || current.deletedAt != null) return;
      if (await tagBelongsToExperiment(id)) {
        throw StateError(experimentTagRemovalMessage(id));
      }
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
