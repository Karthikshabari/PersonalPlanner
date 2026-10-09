import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/tag_dao.dart';
import '../../../core/models/tag.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';

/// How many blocks carry a tag and the planner-local date (`yyyy-MM-dd`) of
/// the earliest one, or null when there is none.
class TagUsage {
  const TagUsage({required this.blockCount, required this.firstBlockDate});

  final int blockCount;
  final String? firstBlockDate;
}

/// Tags label blocks (one per block, `tasks.tag_id`) and back experiments.
/// The legacy `task_tags` helpers stay for sync, recurrence and backup code.
class TagRepository {
  final AppDatabase _db;

  TagRepository(this._db);

  TagDao get _dao => _db.tagDao;

  /// The key used to FIND an existing tag (ED5): trimmed, every run of inner
  /// whitespace collapsed to one space, lower-cased. Never use it as a name
  /// or pass it to [getOrCreateByName], which keeps the deterministic id
  /// formula `tag:<trimmed name as typed>`.
  static String normalizeTagKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// The active tag whose [normalizeTagKey] equals the input's, or null.
  /// When several active tags share the key (ED4) the one created first wins,
  /// then the smallest id.
  Future<Tag?> findByNameIgnoringCase(String name) async {
    final key = normalizeTagKey(name);
    if (key.isEmpty) return null;
    for (final row in await _dao.getActiveTags()) {
      if (normalizeTagKey(row.name) == key) return _fromRow(row);
    }
    return null;
  }

  /// Finds the tag [name] refers to, ignoring case and spacing, or creates it
  /// with the trimmed text as typed.
  Future<Tag> getOrCreateForName(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
    return await findByNameIgnoringCase(name) ?? await getOrCreateByName(name);
  }

  /// Number of non-deleted, non-Inbox blocks that carry [tagId] and the
  /// planner-local date of the earliest one.
  Future<TagUsage> getUsage(String tagId) async {
    final usage = await _dao.getTagUsage(tagId);
    final first = usage.firstStart;
    return TagUsage(
      blockCount: usage.blockCount,
      firstBlockDate: first == null ? null : isoDateString(first),
    );
  }

  Future<Tag> insertTag(Tag tag) async {
    final now = DateTime.now();
    final normalizedName = tag.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(tag.name, 'name', 'must not be blank');
    }
    var effective = tag.copyWith(
      id: tag.id.isEmpty
          ? generateDeterministicUuid('tag:$normalizedName')
          : tag.id,
      name: normalizedName,
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
    final sameId = await _dao.getTagById(effective.id);
    if (sameId != null) {
      if (sameId.deletedAt == null && sameId.name != effective.name) {
        if (tag.id.isNotEmpty) {
          throw StateError(
            'Tag ID ${effective.id} is already named "${sameId.name}". '
            'Rename or delete that tag before recreating "${effective.name}".',
          );
        }
        // The deterministic identity now belongs to a renamed tag. Keep
        // it and give the recreated name a fresh identity.
        effective = effective.copyWith(id: generateUuidV7());
      }
      if (sameId.deletedAt != null) {
        final restored = sameId.copyWith(
          name: effective.name,
          updatedAt: now,
          deletedAt: const Value(null),
          syncStatus: 1,
          revision: sameId.revision + 1,
        );
        await _dao.updateTag(restored);
        return _fromRow(restored);
      }
    }
    await _dao.insertTag(_toCompanion(effective));
    final inserted = await _dao.getTagById(effective.id);
    if (inserted == null || inserted.name != effective.name) {
      throw StateError(
        'Tag "${effective.name}" could not be persisted because its ID is in use.',
      );
    }
    return _fromRow(inserted);
  }

  /// Finds or creates the tag with [name] and returns its id.
  Future<Tag> getOrCreateByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
    final existing = await _dao.getTagByName(trimmed);
    if (existing != null && existing.deletedAt == null) {
      return _fromRow(existing);
    }
    final deterministicId = generateDeterministicUuid('tag:$trimmed');
    final deterministic = await _dao.getTagById(deterministicId);
    if (deterministic != null) {
      if (deterministic.deletedAt == null && deterministic.name != trimmed) {
        return insertTag(
          Tag(
            id: generateUuidV7(),
            name: trimmed,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (deterministic.deletedAt != null) {
        final now = DateTime.now();
        await _dao.updateTag(
          deterministic.copyWith(
            name: trimmed,
            updatedAt: now,
            deletedAt: const Value(null),
            syncStatus: 1,
            revision: deterministic.revision + 1,
          ),
        );
      }
      return _fromRow(await _dao.getTagById(deterministicId) ?? deterministic);
    }
    return insertTag(
      Tag(
        id: deterministicId,
        name: trimmed,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Refuses (StateError) while an experiment uses the tag (ED18).
  Future<void> deleteTag(String id) async {
    if (await _dao.tagBelongsToExperiment(id)) {
      throw StateError(experimentTagRemovalMessage(id));
    }
    await _dao.softDeleteTag(id, DateTime.now());
  }

  Future<Tag> updateTag(Tag tag) async {
    final row = await _dao.getTagById(tag.id);
    if (row == null || row.deletedAt != null) {
      throw StateError('Tag ${tag.id} not found');
    }
    final name = tag.name.trim();
    if (name.isEmpty) throw ArgumentError('Tag name must not be blank');
    final sameName = await _dao.getTagByName(name);
    if (sameName != null &&
        sameName.deletedAt == null &&
        sameName.id != tag.id) {
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
    final rows =
        await (_db.select(_db.tags).join([
              innerJoin(
                _db.taskTags,
                _db.taskTags.tagId.equalsExp(_db.tags.id),
              ),
            ])..where(
              _db.tags.deletedAt.isNull() &
                  _db.taskTags.deletedAt.isNull() &
                  _db.taskTags.taskId.equals(taskId),
            ))
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
      final current =
          await (_db.select(_db.taskTags)..where(
                (link) => link.taskId.equals(taskId) & link.deletedAt.isNull(),
              ))
              .get();
      final currentIds = current.map((link) => link.tagId).toSet();
      for (final tagId in currentIds.difference(tagIds)) {
        await _dao.unlinkTaskTag(taskId, tagId);
      }
      for (final tagId in tagIds.difference(currentIds)) {
        final tag =
            await (_db.select(_db.tags)
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
