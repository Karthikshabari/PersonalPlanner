import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/tag_dao.dart';
import '../../../core/models/tag.dart';
import '../../../core/utils/uuid.dart';

class TagRepository {
  final AppDatabase _db;

  TagRepository(this._db);

  TagDao get _dao => _db.tagDao;

  Future<Tag> insertTag(Tag tag) async {
    final now = DateTime.now();
    final effective = tag.copyWith(
      id: tag.id.isEmpty ? generateUuidV7() : tag.id,
      createdAt: now,
      updatedAt: now,
    );
    final existing = await _dao.getTagByName(effective.name);
    if (existing != null) {
      if (existing.deletedAt == null) return _fromRow(existing);
      final restored = existing.copyWith(
        name: effective.name,
        updatedAt: now,
        deletedAt: const Value(null),
        syncStatus: 1,
        revision: existing.revision + 1,
      );
      await _dao.updateTag(restored);
      return _fromRow(restored);
    }
    await _dao.insertTag(_toCompanion(effective));
    // insertOrIgnore: if a tag with this name already exists, return it.
    final inserted = await _dao.getTagByName(effective.name);
    return inserted == null ? effective : _fromRow(inserted);
  }

  /// Finds or creates the tag with [name] and returns its id.
  Future<Tag> getOrCreateByName(String name) async {
    final trimmed = name.trim();
    final existing = await _dao.getTagByName(trimmed);
    if (existing != null && existing.deletedAt == null) return _fromRow(existing);
    return insertTag(
        Tag(id: '', name: trimmed, createdAt: DateTime.now(), updatedAt: DateTime.now()));
  }

  Future<void> deleteTag(String id) => _dao.softDeleteTag(id, DateTime.now());

  Future<Tag> updateTag(Tag tag) async {
    final row = await _dao.getTagById(tag.id);
    if (row == null || row.deletedAt != null) {
      throw StateError('Tag ${tag.id} not found');
    }
    final name = tag.name.trim();
    if (name.isEmpty) throw ArgumentError('Tag name must not be blank');
    final sameName = await _dao.getTagByName(name);
    if (sameName != null && sameName.deletedAt == null && sameName.id != tag.id) {
      throw StateError('A tag named "$name" already exists');
    }
    final updated = row.copyWith(
      name: name,
      updatedAt: DateTime.now(),
      syncStatus: 1,
      revision: row.revision + 1,
    );
    await _dao.updateTag(updated);
    return _fromRow(updated);
  }

  Stream<List<Tag>> watchAllTags() =>
      _dao.watchActiveTags().map((rows) => rows.map(_fromRow).toList());

  Stream<List<Tag>> watchTagsForTask(String taskId) =>
      _dao.watchTagsForTask(taskId).map((rows) => rows.map(_fromRow).toList());

  Future<List<Tag>> getTagsForTask(String taskId) async {
    final rows = await (_db.select(_db.tags).join([
      innerJoin(_db.taskTags, _db.taskTags.tagId.equalsExp(_db.tags.id)),
    ])
          ..where(_db.tags.deletedAt.isNull() &
              _db.taskTags.deletedAt.isNull() &
              _db.taskTags.taskId.equals(taskId)))
        .get();
    return rows.map((r) => _fromRow(r.readTable(_db.tags))).toList();
  }

  Future<void> addTagToTask(String taskId, String tagId) =>
      _dao.linkTaskTag(taskId, tagId, DateTime.now());

  Future<void> removeTagFromTask(String taskId, String tagId) =>
      _dao.unlinkTaskTag(taskId, tagId);

  /// Reconciles a staged editor selection in one database transaction.
  Future<void> replaceTagsForTask(String taskId, Set<String> tagIds) async {
    await _db.transaction(() async {
      final current = await (_db.select(_db.taskTags)
            ..where((link) =>
                link.taskId.equals(taskId) & link.deletedAt.isNull()))
          .get();
      final currentIds = current.map((link) => link.tagId).toSet();
      for (final tagId in currentIds.difference(tagIds)) {
        await _dao.unlinkTaskTag(taskId, tagId);
      }
      for (final tagId in tagIds.difference(currentIds)) {
        final tag = await (_db.select(_db.tags)
              ..where((t) => t.id.equals(tagId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (tag != null) {
          await _dao.linkTaskTag(taskId, tagId, DateTime.now());
        }
      }
    });
  }

  static Tag _fromRow(TagRow row) => Tag(
        id: row.id,
        name: row.name,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  static TagsCompanion _toCompanion(Tag t) => TagsCompanion.insert(
        id: t.id,
        name: t.name,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
        deletedAt: Value(t.deletedAt),
        syncStatus: const Value(1),
        revision: const Value(1),
      );
}
