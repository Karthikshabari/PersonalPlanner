import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/timeline/domain/commands/batch_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/command_history.dart';
import 'package:personal_planner/features/timeline/domain/commands/scheduling_command.dart';
import 'package:personal_planner/features/timeline/presentation/providers/undo_stack_provider.dart';

import '../../helpers/sqlite_setup.dart';

class FakeCommand implements SchedulingCommand {
  final String name;
  final List<String> log;
  int executed = 0;
  int undone = 0;

  FakeCommand(this.name, this.log);

  @override
  String get description => name;

  @override
  Future<void> execute() async {
    executed++;
    log.add('exec:$name');
  }

  @override
  Future<void> undo() async {
    undone++;
    log.add('undo:$name');
  }
}

void main() {
  group('CommandHistoryState', () {
    test('push clears the redo stack and enforces the 50-item cap', () {
      var state = const CommandHistoryState();
      for (var i = 0; i < CommandHistoryState.maxUndoEntries + 10; i++) {
        state = state.push(FakeCommand('c$i', []));
      }
      expect(state.undoStack.length, CommandHistoryState.maxUndoEntries);
      expect(state.undoStack.last.description, 'c59');
      expect(state.undoStack.first.description, 'c10');

      // Pushing after undo must clear redo.
      var s2 = const CommandHistoryState();
      s2 = s2.push(FakeCommand('a', []));
      s2 = s2.push(FakeCommand('b', []));
      s2 = s2.popUndo();
      expect(s2.canRedo, isTrue);
      s2 = s2.push(FakeCommand('c', []));
      expect(s2.canRedo, isFalse);
    });

    test('popUndo / popRedo move commands between stacks', () {
      var state = const CommandHistoryState();
      state = state.push(FakeCommand('a', []));
      state = state.push(FakeCommand('b', []));
      expect(state.canUndo, isTrue);

      state = state.popUndo();
      expect(state.undoStack.length, 1);
      expect(state.redoStack.single.description, 'b');

      state = state.popRedo();
      expect(state.redoStack, isEmpty);
      expect(state.undoStack.length, 2);
      expect(state.canRedo, isFalse);
    });
  });

  group('UndoStackNotifier', () {
    late ProviderContainer container;
    late AppDatabase database;
    late List<String> log;

    setUp(() {
      setupSqliteForTests();
      log = [];
      database = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('execute → undo → redo round trip', () async {
      final notifier = container.read(undoStackProvider.notifier);
      final a = FakeCommand('a', log);
      final b = FakeCommand('b', log);

      await notifier.execute(a);
      await notifier.execute(b);
      expect(container.read(undoStackProvider).canUndo, isTrue);
      expect(log, ['exec:a', 'exec:b']);

      expect(await notifier.undo(), 'b');
      expect(log, ['exec:a', 'exec:b', 'undo:b']);
      expect(await notifier.redo(), 'b');
      expect(log.last, 'exec:b');

      expect(await notifier.undo(), 'b');
      expect(await notifier.undo(), 'a');
      expect(await notifier.undo(), isNull);
      expect(container.read(undoStackProvider).canUndo, isFalse);
      expect(container.read(undoStackProvider).canRedo, isTrue);
      expect(await notifier.redo(), 'a');
    });
  });

  group('BatchCommand', () {
    test('executes in order, undoes in REVERSE order', () async {
      final log = <String>[];
      final batch = BatchCommand([
        FakeCommand('1', log),
        FakeCommand('2', log),
        FakeCommand('3', log),
      ]);
      await batch.execute();
      expect(log, ['exec:1', 'exec:2', 'exec:3']);
      log.clear();
      await batch.undo();
      expect(log, ['undo:3', 'undo:2', 'undo:1']);
    });
  });
}
