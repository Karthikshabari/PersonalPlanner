import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';

import '../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('every opened connection waits 30 s for locks held elsewhere', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: AppDatabase.configureConnection),
    );
    addTearDown(database.close);

    final row = await database.customSelect('PRAGMA busy_timeout').getSingle();

    expect(row.data.values.single, 30000);
  });
}
