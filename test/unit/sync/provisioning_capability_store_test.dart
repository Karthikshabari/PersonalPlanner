import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/data/provisioning_capability_store.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';

const _transactionA = '0123456789abcdef0123456789abcdef';
const _transactionB = 'fedcba9876543210fedcba9876543210';
const _capability = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD';

class _FakeSecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<String?> read({required String key}) async {
    if (failReads) throw StateError('keyring unavailable');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrites) throw StateError('keyring unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    if (failDeletes) throw StateError('keyring unavailable');
    values.remove(key);
  }
}

void main() {
  late _FakeSecureStore raw;
  late SecureProvisioningCapabilityStore store;

  setUp(() {
    raw = _FakeSecureStore();
    store = SecureProvisioningCapabilityStore(storage: raw);
  });

  test('stores a capability under the provisioning namespace only', () async {
    await store.write(transactionId: _transactionA, capability: _capability);

    expect(
      raw.values.keys.single,
      '${SecureProvisioningCapabilityStore.keyPrefix}$_transactionA',
    );
    expect(raw.values.keys.single, isNot(contains('supabase')));
    expect(await store.read(transactionId: _transactionA), _capability);
  });

  test('an absent capability reads as null and delete is repeatable', () async {
    expect(await store.read(transactionId: _transactionA), isNull);

    await store.write(transactionId: _transactionA, capability: _capability);
    await store.delete(transactionId: _transactionA);
    await store.delete(transactionId: _transactionA);

    expect(await store.read(transactionId: _transactionA), isNull);
  });

  test('one transaction cannot read, overwrite or delete another', () async {
    await store.write(transactionId: _transactionA, capability: _capability);

    expect(await store.read(transactionId: _transactionB), isNull);
    await store.delete(transactionId: _transactionB);
    expect(await store.read(transactionId: _transactionA), _capability);

    const otherCapability = 'ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210zyxw';
    await store.write(
      transactionId: _transactionB,
      capability: otherCapability,
    );
    expect(await store.read(transactionId: _transactionA), _capability);
    expect(await store.read(transactionId: _transactionB), otherCapability);
    expect(raw.values, hasLength(2));
  });

  test('rejects transaction ids that are not 32 character hex ids', () async {
    for (final transactionId in <String>[
      '',
      '0123456789abcdef0123456789abcde',
      '0123456789ABCDEF0123456789abcdef',
      '0123456789abcdef0123456789abcdeg',
      'tx:/../0123456789abcdef0123456789abcdef',
    ]) {
      await expectLater(
        store.write(transactionId: transactionId, capability: _capability),
        throwsA(
          isA<ProvisioningCapabilityStoreException>().having(
            (error) => error.failure,
            'failure',
            ProvisioningCapabilityFailure.malformed,
          ),
        ),
        reason: transactionId,
      );
      await expectLater(
        store.read(transactionId: transactionId),
        throwsA(isA<ProvisioningCapabilityStoreException>()),
      );
      await expectLater(
        store.delete(transactionId: transactionId),
        throwsA(isA<ProvisioningCapabilityStoreException>()),
      );
    }
    expect(raw.values, isEmpty);
  });

  test('refuses to store a malformed capability', () async {
    for (final capability in <String>[
      '',
      'too-short',
      'has spaces in it and is long enough to pass length',
      'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789',
    ]) {
      await expectLater(
        store.write(transactionId: _transactionA, capability: capability),
        throwsA(
          isA<ProvisioningCapabilityStoreException>().having(
            (error) => error.failure,
            'failure',
            ProvisioningCapabilityFailure.malformed,
          ),
        ),
        reason: capability,
      );
    }
    expect(raw.values, isEmpty);
  });

  test('rejects a malformed stored value instead of returning it', () async {
    raw.values[SecureProvisioningCapabilityStore.keyPrefix + _transactionA] =
        'not a capability';

    await expectLater(
      store.read(transactionId: _transactionA),
      throwsA(
        isA<ProvisioningCapabilityStoreException>().having(
          (error) => error.failure,
          'failure',
          ProvisioningCapabilityFailure.malformed,
        ),
      ),
    );
  });

  test(
    'reports unavailable secure storage rather than a missing value',
    () async {
      raw.failReads = true;

      await expectLater(
        store.read(transactionId: _transactionA),
        throwsA(
          isA<ProvisioningCapabilityStoreException>().having(
            (error) => error.failure,
            'failure',
            ProvisioningCapabilityFailure.unavailable,
          ),
        ),
      );
    },
  );

  test('reports write and delete failures as unavailable', () async {
    raw.failWrites = true;
    await expectLater(
      store.write(transactionId: _transactionA, capability: _capability),
      throwsA(
        isA<ProvisioningCapabilityStoreException>().having(
          (error) => error.failure,
          'failure',
          ProvisioningCapabilityFailure.unavailable,
        ),
      ),
    );

    raw.failWrites = false;
    await store.write(transactionId: _transactionA, capability: _capability);
    raw.failDeletes = true;
    await expectLater(
      store.delete(transactionId: _transactionA),
      throwsA(
        isA<ProvisioningCapabilityStoreException>().having(
          (error) => error.failure,
          'failure',
          ProvisioningCapabilityFailure.unavailable,
        ),
      ),
    );
    expect(await store.read(transactionId: _transactionA), _capability);
  });
}
