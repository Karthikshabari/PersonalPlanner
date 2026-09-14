import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/settings/data/backup_service.dart';

void main() {
  test(
    'recovery snapshots use unique exclusive files and retain both contents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planner_recovery',
      );
      addTearDown(() => directory.delete(recursive: true));

      final first = await BackupRecoveryWriter.write(
        directoryPath: directory.path,
        contents: 'snapshot A',
      );
      final second = await BackupRecoveryWriter.write(
        directoryPath: directory.path,
        contents: 'snapshot B',
      );

      expect(first.path, isNot(second.path));
      expect(await first.readAsString(), 'snapshot A');
      expect(await second.readAsString(), 'snapshot B');
      expect(first.path, contains('personal_planner_pre_import_'));
    },
  );
}
