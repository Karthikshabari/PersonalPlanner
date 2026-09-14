import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';

void main() {
  test(
    'sign-out deletion waits for an earlier delayed refresh write',
    () async {
      final store = _FakeSecureStore()..delayNextWrite = Completer<void>();
      final adapter = SecureSupabaseLocalStorage(storage: store);

      final write = adapter.persistSession('old-refresh-value');
      final remove = adapter.removePersistedSession();
      expect(store.operations, isEmpty);

      store.delayNextWrite!.complete();
      await write;
      await remove;
      await adapter.settle();

      expect(store.operations, ['write', 'delete']);
      expect(store.value, isNull);
    },
  );

  test('a failed secure write does not poison later operations', () async {
    final outcomes = <SecureSessionStorageOutcome>[];
    final store = _FakeSecureStore()..failNextWrite = true;
    final adapter = SecureSupabaseLocalStorage(
      storage: store,
      onOutcome: outcomes.add,
    );

    await expectLater(adapter.persistSession('first'), throwsStateError);
    await adapter.persistSession('second');
    await adapter.settle();

    expect(store.value, 'second');
    expect(
      outcomes.where((outcome) => !outcome.succeeded).single.code,
      contains('persistSession'),
    );
    expect(outcomes.last.succeeded, isTrue);
  });

  test(
    'bootstrap collector blocks anonymous fallback after a caught read failure',
    () {
      final collector = SecureSessionBootstrapCollector();
      collector.record(
        const SecureSessionStorageOutcome(
          operation: SecureSessionStorageOperation.accessToken,
          succeeded: false,
          errorType: 'KeyringException',
        ),
      );

      expect(collector.requiresRetry, isTrue);
      expect(
        () => requireSecureSessionBootstrapReady(collector),
        throwsA(isA<SecureSessionBootstrapException>()),
      );
    },
  );
}

class _FakeSecureStore implements SecureKeyValueStore {
  final operations = <String>[];
  String? value;
  Completer<void>? delayNextWrite;
  bool failNextWrite = false;

  @override
  Future<bool> containsKey({required String key}) async => value != null;

  @override
  Future<void> delete({required String key}) async {
    operations.add('delete');
    value = null;
  }

  @override
  Future<String?> read({required String key}) async => value;

  @override
  Future<void> write({required String key, required String value}) async {
    final delay = delayNextWrite;
    delayNextWrite = null;
    if (delay != null) await delay.future;
    operations.add('write');
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('keyring unavailable');
    }
    this.value = value;
  }
}
