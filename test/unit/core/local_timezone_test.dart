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

  test('Windows daylight zone names resolve like their standard names', () {
    const zones = [
      'GMT',
      'W. Europe',
      'Central Europe',
      'Romance',
      'Central European',
      'E. Europe',
      'GTB',
      'FLE',
      'Eastern',
      'Central',
      'Mountain',
      'Pacific',
      'Alaskan',
      'Atlantic',
      'Newfoundland',
      'Israel',
      'Egypt',
      'AUS Eastern',
      'Cen. Australia',
      'New Zealand',
    ];
    for (final zone in zones) {
      final standard = ianaIdForWindowsName('$zone Standard Time');
      expect(standard, isNotNull, reason: zone);
      expect(ianaIdForWindowsName('$zone Daylight Time'), standard);
    }
    expect(ianaIdForWindowsName('Eastern Daylight Time'), 'America/New_York');
    expect(ianaIdForWindowsName('Unknown Daylight Time'), isNull);
  });
}
