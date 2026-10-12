import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/inbox/domain/inbox_board.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

import '../../helpers/inbox_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupSqliteForTests();

  late AppDatabase db;
  late InboxHarness h;
  late ProviderContainer container;
  late DateTime fakeNow;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    h = InboxHarness(db);
    fakeNow = DateTime.now();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        inboxNowFactoryProvider.overrideWithValue(() => fakeNow),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> until(bool Function() condition, {int seconds = 5}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The condition was not met within $seconds seconds.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  InboxBoard? board() => container.read(inboxBoardProvider).value;

  test('the board loads, and follows writes without being asked', () async {
    final sub = container.listen(inboxBoardProvider, (_, _) {});
    addTearDown(sub.close);
    await until(() => board() != null);
    expect(board()!.openCount, 0);

    final idea = await h.idea('A new idea');
    await until(() => board()!.ideas.contains(idea.id));

    await h.inbox.createSession(
      idea.id,
      fakeNow.add(const Duration(hours: 2)),
      fakeNow.add(const Duration(hours: 3)),
      now: fakeNow,
    );
    await until(() => board()!.comingUp.contains(idea.id));
    expect(board()!.ideas, isEmpty);

    await h.inbox.closeItem(idea.id, 'Not needed', fakeNow);
    await until(() => board()!.done.contains(idea.id));
    expect(board()!.byId[idea.id]!.chip, 'Closed');
    expect(board()!.openCount, 0);
    expect(board()!.doneCount, 1);
  });

  test(
    'a write to an unrelated row does not change the board object',
    () async {
      final sub = container.listen(inboxBoardProvider, (_, _) {});
      addTearDown(sub.close);
      final idea = await h.idea('Stays put');
      await until(() => board()?.ideas.contains(idea.id) ?? false);
      final first = board();
      var emissions = 0;
      final listener = container.listen(
        inboxSourceProvider,
        (_, _) => emissions++,
      );
      addTearDown(listener.close);
      // A plain Day task changes `tasks` but not what the Inbox reads.
      await h.tasks.insertTask(
        (await h.tasks.getTaskById(idea.id))!.copyWith(
          id: '',
          isInbox: false,
          startTime: fakeNow.add(const Duration(days: 1)),
          endTime: fakeNow.add(const Duration(days: 1, hours: 1)),
          title: 'Unrelated',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(emissions, 0, reason: 'an unchanged source is not emitted');
      expect(identical(board(), first), isTrue);
    },
  );

  test('one timer moves the clock past the next boundary', () async {
    final idea = await h.idea('Ends soon');
    final end = fakeNow.add(const Duration(seconds: 1));
    await h.tasks.insertTask(
      (await h.tasks.getTaskById(idea.id))!.copyWith(
        id: '',
        isInbox: false,
        inboxItemId: idea.id,
        title: 'In progress',
        startTime: fakeNow.subtract(const Duration(hours: 1)),
        endTime: end,
      ),
    );
    final sub = container.listen(inboxBoardProvider, (_, _) {});
    addTearDown(sub.close);
    await until(() => board()?.byId[idea.id] != null);
    expect(board()!.byId[idea.id]!.status, InboxItemStatus.soon);
    expect(board()!.nextBoundary, sameInstantAs(end));

    // Time passes (the test controls the clock); the one-shot timer fires at
    // the boundary and the same board now says the session was missed.
    fakeNow = end.add(const Duration(milliseconds: 50));
    await until(() => board()!.byId[idea.id]!.status == InboxItemStatus.left);
    expect(board()!.leftOver, [idea.id]);
    expect(board()!.reasonsMissing.count, 1);
  });

  test(
    'closing the screen stops the clock (no timer survives dispose)',
    () async {
      final sub = container.listen(inboxBoardProvider, (_, _) {});
      await until(() => board() != null);
      final before = container.read(inboxScreenClockProvider);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Auto-dispose: reading again builds a fresh clock from the factory.
      fakeNow = fakeNow.add(const Duration(hours: 1));
      final after = container.read(inboxScreenClockProvider);
      expect(after.isAfter(before), isTrue);
    },
  );

  test('the expanded and focus providers start empty', () {
    expect(container.read(inboxExpandedItemProvider), isNull);
    expect(container.read(inboxFocusItemProvider), isNull);
    container.read(inboxExpandedItemProvider.notifier).state = 'a';
    expect(container.read(inboxExpandedItemProvider), 'a');
  });
}

Matcher sameInstantAs(DateTime expected) => predicate<DateTime>(
  (actual) => actual.isAtSameMomentAs(expected),
  'the instant ${expected.toIso8601String()}',
);
