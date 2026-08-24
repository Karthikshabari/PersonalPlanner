import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String generateUuidV7() => _uuid.v7();
