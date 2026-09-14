import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'backup_format.dart';

/// Reads backup input without allocating an unbounded byte/string copy before
/// the documented size limit is enforced.
abstract final class BackupInputReader {
  static Future<Uint8List> read(PlatformFile file) async {
    int? reportedLength;
    try {
      reportedLength = await file.length();
    } on Object {
      // Some providers cannot report metadata. The stream limit below remains
      // authoritative in that case.
    }
    if (reportedLength != null && reportedLength > plannerBackupMaxBytes) {
      throw const BackupValidationException(
        'Backup file exceeds the 20 MiB size limit',
      );
    }
    return fromStream(file.readAsByteStream());
  }

  static Future<Uint8List> fromStream(
    Stream<List<int>> stream, {
    int? reportedLength,
  }) async {
    if (reportedLength != null && reportedLength > plannerBackupMaxBytes) {
      throw const BackupValidationException(
        'Backup file exceeds the 20 MiB size limit',
      );
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > plannerBackupMaxBytes) {
        throw const BackupValidationException(
          'Backup file exceeds the 20 MiB size limit',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
