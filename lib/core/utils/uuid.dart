import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String generateUuidV7() => _uuid.v7();

/// Returns a stable UUID for a logical value.
///
/// The namespace is application-owned so callers can use the same canonical
/// key on every device without changing the UUIDs of existing rows.
String generateDeterministicUuid(String key) =>
    _uuid.v5(Namespace.url.value, 'personal-planner:$key');
