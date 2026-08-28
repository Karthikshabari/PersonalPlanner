// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timer_dao.dart';

// ignore_for_file: type=lint
mixin _$TimerDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $RecurringRulesTable get recurringRules => attachedDatabase.recurringRules;
  $TasksTable get tasks => attachedDatabase.tasks;
  $TimerSessionsTable get timerSessions => attachedDatabase.timerSessions;
  TimerDaoManager get managers => TimerDaoManager(this);
}

class TimerDaoManager {
  final _$TimerDaoMixin _db;
  TimerDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$RecurringRulesTableTableManager get recurringRules =>
      $$RecurringRulesTableTableManager(
        _db.attachedDatabase,
        _db.recurringRules,
      );
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$TimerSessionsTableTableManager get timerSessions =>
      $$TimerSessionsTableTableManager(_db.attachedDatabase, _db.timerSessions);
}
