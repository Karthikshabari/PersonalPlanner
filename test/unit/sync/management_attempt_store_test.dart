import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/management_attempt_store.dart';

import '../../helpers/runtime_auth_fakes.dart';

void main() {
  late FakeSecureKeyValueStore storage;
  late ManagementAttemptStore store;

  setUp(() {
    storage = FakeSecureKeyValueStore();
    store = ManagementAttemptStore(storage: storage);
  });

  test('round trips one in-flight authorization', () async {
    await store.write(
      const ManagementAttempt(
        transactionId: '0123456789abcdef0123456789abcdef',
        capability: 'abcdefghijklmnopqrstuvwxyz0123456789ABCD',
        projectRef: 'abcdefghijklmnopqrst',
      ),
    );

    final restored = await store.read();
    expect(restored?.transactionId, '0123456789abcdef0123456789abcdef');
    expect(restored?.projectRef, 'abcdefghijklmnopqrst');
    expect(restored.toString(), isNot(contains('ABCD')));
  });

  test('never trusts a malformed stored value', () async {
    for (final value in <String>[
      'not json',
      '{"transactionId":"short","capability":"abc","projectRef":"x"}',
      '{"transactionId":"0123456789abcdef0123456789abcdef","capability":"short","projectRef":"abcdefghijklmnopqrst"}',
      '{"transactionId":"0123456789abcdef0123456789abcdef","capability":"abcdefghijklmnopqrstuvwxyz0123456789ABCD","projectRef":"NOTAREF"}',
      '[]',
    ]) {
      storage.values[ManagementAttemptStore.storageKey] = value;
      expect(await store.read(), isNull, reason: value);
      // A value this build cannot trust is not kept around.
      expect(
        storage.values.containsKey(ManagementAttemptStore.storageKey),
        isFalse,
      );
    }
  });

  test('clearing removes the credential', () async {
    await store.write(
      const ManagementAttempt(
        transactionId: '0123456789abcdef0123456789abcdef',
        capability: 'abcdefghijklmnopqrstuvwxyz0123456789ABCD',
        projectRef: 'abcdefghijklmnopqrst',
      ),
    );
    await store.clear();

    expect(await store.read(), isNull);
    expect(storage.values, isEmpty);
  });
}
