// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_dao.dart';

// ignore_for_file: type=lint
mixin _$TemplateDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $TaskTemplatesTable get taskTemplates => attachedDatabase.taskTemplates;
  TemplateDaoManager get managers => TemplateDaoManager(this);
}

class TemplateDaoManager {
  final _$TemplateDaoMixin _db;
  TemplateDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TaskTemplatesTableTableManager get taskTemplates =>
      $$TaskTemplatesTableTableManager(_db.attachedDatabase, _db.taskTemplates);
}
