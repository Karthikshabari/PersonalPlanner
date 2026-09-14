import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/settings/data/backup_format.dart';
import 'package:personal_planner/features/settings/data/backup_input.dart';

Stream<List<int>> _chunks(int length) async* {
  var remaining = length;
  while (remaining > 0) {
    final size = remaining.clamp(1, 4096).toInt();
    yield Uint8List(size);
    remaining -= size;
  }
}

void main() {
  test('accepts a stream at the exact backup limit', () async {
    final bytes = await BackupInputReader.fromStream(
      _chunks(plannerBackupMaxBytes),
      reportedLength: plannerBackupMaxBytes,
    );
    expect(bytes.length, plannerBackupMaxBytes);
  });

  test('rejects a stream once it exceeds the backup limit', () async {
    await expectLater(
      BackupInputReader.fromStream(_chunks(plannerBackupMaxBytes + 1)),
      throwsA(isA<BackupValidationException>()),
    );
  });

  test('rejects oversized metadata before reading the stream', () async {
    var read = false;
    final stream = (() async* {
      read = true;
      yield <int>[1];
    })();
    await expectLater(
      BackupInputReader.fromStream(
        stream,
        reportedLength: plannerBackupMaxBytes + 1,
      ),
      throwsA(isA<BackupValidationException>()),
    );
    expect(read, isFalse);
  });
}
