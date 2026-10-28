import 'dart:io';

import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

const MethodChannel _channel = MethodChannel('personal_planner/timezone');

/// Windows 'Standard Time' display names -> IANA ids for the common zones.
/// Anything missing falls back to an offset match, then UTC.
const Map<String, String> _windowsZones = {
  'UTC': 'UTC',
  'GMT Standard Time': 'Europe/London',
  'W. Europe Standard Time': 'Europe/Berlin',
  'Central Europe Standard Time': 'Europe/Budapest',
  'Romance Standard Time': 'Europe/Paris',
  'Central European Standard Time': 'Europe/Warsaw',
  'E. Europe Standard Time': 'Europe/Chisinau',
  'GTB Standard Time': 'Europe/Bucharest',
  'FLE Standard Time': 'Europe/Kiev',
  'Russian Standard Time': 'Europe/Moscow',
  'Eastern Standard Time': 'America/New_York',
  'Central Standard Time': 'America/Chicago',
  'Mountain Standard Time': 'America/Denver',
  'US Mountain Standard Time': 'America/Phoenix',
  'Pacific Standard Time': 'America/Los_Angeles',
  'Alaskan Standard Time': 'America/Anchorage',
  'Hawaiian Standard Time': 'Pacific/Honolulu',
  'Canada Central Standard Time': 'America/Regina',
  'Atlantic Standard Time': 'America/Halifax',
  'Newfoundland Standard Time': 'America/St_Johns',
  'E. South America Standard Time': 'America/Sao_Paulo',
  'Argentina Standard Time': 'America/Argentina/Buenos_Aires',
  'India Standard Time': 'Asia/Kolkata',
  'Sri Lanka Standard Time': 'Asia/Colombo',
  'Nepal Standard Time': 'Asia/Kathmandu',
  'Pakistan Standard Time': 'Asia/Karachi',
  'Arabian Standard Time': 'Asia/Dubai',
  'Arab Standard Time': 'Asia/Riyadh',
  'Israel Standard Time': 'Asia/Jerusalem',
  'Turkey Standard Time': 'Europe/Istanbul',
  'Egypt Standard Time': 'Africa/Cairo',
  'South Africa Standard Time': 'Africa/Johannesburg',
  'W. Central Africa Standard Time': 'Africa/Lagos',
  'E. Africa Standard Time': 'Africa/Nairobi',
  'China Standard Time': 'Asia/Shanghai',
  'Taipei Standard Time': 'Asia/Taipei',
  'Singapore Standard Time': 'Asia/Singapore',
  'SE Asia Standard Time': 'Asia/Bangkok',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'Korea Standard Time': 'Asia/Seoul',
  'AUS Eastern Standard Time': 'Australia/Sydney',
  'E. Australia Standard Time': 'Australia/Brisbane',
  'Cen. Australia Standard Time': 'Australia/Adelaide',
  'W. Australia Standard Time': 'Australia/Perth',
  'New Zealand Standard Time': 'Pacific/Auckland',
};

const _standardSuffix = ' Standard Time';
const _daylightSuffix = ' Daylight Time';

/// IANA id for a Windows zone display name, or null when it is not mapped.
/// Dart reports the 'Daylight Time' name while summer time is in force; it
/// resolves through the zone's 'Standard Time' key.
String? ianaIdForWindowsName(String name) {
  final key = name.endsWith(_daylightSuffix)
      ? '${name.substring(0, name.length - _daylightSuffix.length)}'
            '$_standardSuffix'
      : name;
  return _windowsZones[key];
}

/// Resolves the device's IANA timezone id without any native plugin DLL.
///
/// Android asks `java.util.TimeZone` through a tiny MethodChannel; Linux reads
/// `/etc/localtime` or `/etc/timezone`; Windows maps the display name. Every
/// path ends in an offset match and then UTC, and this never throws.
Future<String> resolveLocalTimezoneId() async {
  try {
    final id = await _platformId();
    if (id != null && _isKnown(id)) return id;
  } on Object {
    // Fall through to the offset match.
  }
  return _byOffset() ?? 'UTC';
}

Future<String?> _platformId() async {
  if (Platform.isAndroid) {
    return _channel.invokeMethod<String>('getLocalTimezone');
  }
  if (Platform.isLinux || Platform.isMacOS) {
    final fromEnv = Platform.environment['TZ']?.replaceFirst(RegExp('^:'), '');
    if (fromEnv != null && _isKnown(fromEnv)) return fromEnv;
    try {
      final target = await Link('/etc/localtime').resolveSymbolicLinks();
      final match = RegExp(r'zoneinfo/(.+)$').firstMatch(target);
      if (match != null) return match.group(1);
    } on Object {
      // Not a symlink; try /etc/timezone.
    }
    final file = File('/etc/timezone');
    if (await file.exists()) return (await file.readAsString()).trim();
    return null;
  }
  if (Platform.isWindows) {
    return ianaIdForWindowsName(DateTime.now().timeZoneName);
  }
  return null;
}

bool _isKnown(String id) {
  try {
    tz.getLocation(id);
    return true;
  } on Object {
    return false;
  }
}

/// First IANA location whose current offset equals the host offset.
String? _byOffset() {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  for (final id in const [
    'UTC',
    'Europe/London',
    'Europe/Berlin',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Asia/Kolkata',
    'Asia/Shanghai',
    'Asia/Tokyo',
    'Australia/Sydney',
  ]) {
    if (tz.TZDateTime.from(now, tz.getLocation(id)).timeZoneOffset == offset) {
      return id;
    }
  }
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (tz.TZDateTime.from(now, location).timeZoneOffset == offset) {
      return location.name;
    }
  }
  return null;
}
