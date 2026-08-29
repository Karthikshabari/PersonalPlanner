import 'dart:ffi';

import 'package:sqlite3/open.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

bool _configured = false;

void setupSqliteForTests() {
  if (_configured) return;
  _configured = true;
  // Test fixtures use Dart's local wall-clock constructors. Keep that
  // deterministic on the development environment while production startup
  // selects the device's actual IANA zone.
  PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}
