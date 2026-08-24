import 'dart:ffi';

import 'package:sqlite3/open.dart';

bool _configured = false;

void setupSqliteForTests() {
  if (_configured) return;
  _configured = true;
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}
