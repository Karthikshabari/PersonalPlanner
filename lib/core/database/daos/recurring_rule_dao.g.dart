// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_rule_dao.dart';

// ignore_for_file: type=lint
mixin _$RecurringRuleDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $RecurringRulesTable get recurringRules => attachedDatabase.recurringRules;
  RecurringRuleDaoManager get managers => RecurringRuleDaoManager(this);
}

class RecurringRuleDaoManager {
  final _$RecurringRuleDaoMixin _db;
  RecurringRuleDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$RecurringRulesTableTableManager get recurringRules =>
      $$RecurringRulesTableTableManager(
        _db.attachedDatabase,
        _db.recurringRules,
      );
}
