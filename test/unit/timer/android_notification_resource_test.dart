import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart';

void main() {
  test('Android notification icon is valid and narrowly retained', () async {
    expect(NotificationService.androidNotificationIcon, 'ic_notification');

    final icon = File(
      'android/app/src/main/res/drawable/'
      '${NotificationService.androidNotificationIcon}.xml',
    );
    expect(await icon.exists(), isTrue);
    expect(await icon.readAsString(), contains('<vector'));

    final keep = File('android/app/src/main/res/raw/keep.xml');
    expect(await keep.exists(), isTrue);
    final keepXml = await keep.readAsString();
    expect(
      keepXml,
      contains('@drawable/${NotificationService.androidNotificationIcon}'),
    );
    expect(keepXml, isNot(contains('@drawable/*')));
  });

  test('timer action identifiers remain platform-independent', () {
    expect(NotificationService.timerPauseActionId, 'timer_pause');
    expect(NotificationService.timerResumeActionId, 'timer_resume');
    expect(NotificationService.timerStopActionId, 'timer_stop');
  });
}
