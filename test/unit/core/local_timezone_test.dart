import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/local_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('resolves a known IANA id without a native plugin', () async {
    tzdata.initializeTimeZones();
    final id = await resolveLocalTimezoneId();
    expect(() => tz.getLocation(id), returnsNormally);
  });
}
