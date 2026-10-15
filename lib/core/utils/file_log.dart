import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Appends a timestamped line to `planner_log.txt` next to the executable,
/// falling back to the app documents directory. Never throws.
Future<void> logToFile(
  String message, [
  Object? error,
  StackTrace? stack,
]) async {
  final line = StringBuffer('${DateTime.now().toIso8601String()} $message');
  if (error != null) line.write(' | $error');
  if (stack != null) line.write('\n$stack');
  line.writeln();
  try {
    await File(_primaryPath())
        .writeAsString(line.toString(), mode: FileMode.append, flush: true);
    return;
  } on Object {
    // Install dir may be read-only (Program Files, AppImage); fall back.
  }
  try {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}${Platform.pathSeparator}planner_log.txt')
        .writeAsString(line.toString(), mode: FileMode.append, flush: true);
  } on Object {
    // Logging must never break the app.
  }
}

String _primaryPath() {
  final exe = File(Platform.resolvedExecutable).parent.path;
  return '$exe${Platform.pathSeparator}planner_log.txt';
}
