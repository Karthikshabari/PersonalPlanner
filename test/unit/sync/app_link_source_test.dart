import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/auth_callback.dart';
import 'package:personal_planner/core/config/management_callback.dart';
import 'package:personal_planner/features/sync/data/app_link_source.dart';

/// One app-lifetime source owns the single platform subscription, so both the
/// Planner Auth callback router and the provisioning UI observe every link.
void main() {
  late StreamController<String> platform;

  setUp(() => platform = StreamController<String>.broadcast());
  tearDown(() async {
    await platform.close();
  });

  test('fans one platform link out to every listener', () async {
    final source = AppLinkSource(platformLinks: platform.stream);
    addTearDown(source.dispose);
    await source.start();

    final first = <String>[];
    final second = <String>[];
    final firstSub = source.links.listen(first.add);
    final secondSub = source.links.listen(second.add);
    addTearDown(() async {
      await firstSub.cancel();
      await secondSub.cancel();
    });

    platform.add(AuthCallback.redirectUrl);
    await Future<void>.delayed(Duration.zero);
    expect(first, [AuthCallback.redirectUrl]);
    expect(second, [AuthCallback.redirectUrl]);
  });

  test(
    'replays a Linux cold-start launch argument even before listeners',
    () async {
      const link = 'com.personalplanner.personalplanner://management-callback';
      final source = AppLinkSource(
        platformLinks: platform.stream,
        launchArguments: <String>[link],
      );
      addTearDown(source.dispose);
      await source.start();

      // Buffered until the widget layer attaches.
      final received = <String>[];
      final subscription = source.links.listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(received, <String>[link]);
    },
  );

  test('ignores launch arguments that are not Planner callbacks', () async {
    final source = AppLinkSource(
      platformLinks: platform.stream,
      launchArguments: <String>['--some-flag', 'https://example.test/'],
    );
    addTearDown(source.dispose);
    await source.start();
    final received = <String>[];
    final subscription = source.links.listen(received.add);
    addTearDown(subscription.cancel);
    expect(received, isEmpty);
  });

  test('does not deliver the same cold-start link twice', () async {
    const link = '${AuthCallback.redirectUrl}?code=authorization-code';
    final source = AppLinkSource(
      platformLinks: platform.stream,
      launchArguments: <String>[link],
    );
    addTearDown(source.dispose);
    await source.start();

    final received = <String>[];
    final subscription = source.links.listen(received.add);
    addTearDown(subscription.cancel);

    // The native command-line handler can report the same URI again.
    platform.add(link);
    await Future<void>.delayed(Duration.zero);
    expect(received, <String>[link]);
  });

  test('still delivers a genuine later replay of the same link', () async {
    const link = '${AuthCallback.redirectUrl}?code=authorization-code';
    var now = DateTime.utc(2026, 9, 19, 12);
    final source = AppLinkSource(
      platformLinks: platform.stream,
      launchArguments: <String>[link],
    )..configureForTesting(clock: () => now);
    addTearDown(source.dispose);
    await source.start();

    final received = <String>[];
    final subscription = source.links.listen(received.add);
    addTearDown(subscription.cancel);

    now = now.add(AppLinkSource.duplicateWindow + const Duration(seconds: 1));
    platform.add(link);
    await Future<void>.delayed(Duration.zero);
    expect(received, <String>[link, link]);
  });

  test('classifies the Planner callback destinations', () {
    expect(AppLinkSource.isPlannerLink(AuthCallback.redirectUrl), isTrue);
    expect(AppLinkSource.isPlannerLink(ManagementCallback.redirectUrl), isTrue);
    expect(
      AppLinkSource.isPlannerLink('https://supabase.com/dashboard/project/x'),
      isFalse,
    );
  });

  test('an inert source never emits', () async {
    final source = AppLinkSource.inert();
    addTearDown(source.dispose);
    await source.start();
    final received = <String>[];
    final subscription = source.links.listen(received.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
  });
}
