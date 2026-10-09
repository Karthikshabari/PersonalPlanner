// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'experiment_dao.dart';

// ignore_for_file: type=lint
mixin _$ExperimentDaoMixin on DatabaseAccessor<AppDatabase> {
  $TagsTable get tags => attachedDatabase.tags;
  $ExperimentsTable get experiments => attachedDatabase.experiments;
  $ExperimentCheckInsTable get experimentCheckIns =>
      attachedDatabase.experimentCheckIns;
  $DayContextsTable get dayContexts => attachedDatabase.dayContexts;
  $CategoriesTable get categories => attachedDatabase.categories;
  $RecurringRulesTable get recurringRules => attachedDatabase.recurringRules;
  $TasksTable get tasks => attachedDatabase.tasks;
  ExperimentDaoManager get managers => ExperimentDaoManager(this);
}

class ExperimentDaoManager {
  final _$ExperimentDaoMixin _db;
  ExperimentDaoManager(this._db);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$ExperimentsTableTableManager get experiments =>
      $$ExperimentsTableTableManager(_db.attachedDatabase, _db.experiments);
  $$ExperimentCheckInsTableTableManager get experimentCheckIns =>
      $$ExperimentCheckInsTableTableManager(
        _db.attachedDatabase,
        _db.experimentCheckIns,
      );
  $$DayContextsTableTableManager get dayContexts =>
      $$DayContextsTableTableManager(_db.attachedDatabase, _db.dayContexts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$RecurringRulesTableTableManager get recurringRules =>
      $$RecurringRulesTableTableManager(
        _db.attachedDatabase,
        _db.recurringRules,
      );
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
}
