import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/utils/date_utils.dart';

final selectedDateProvider = StateProvider<DateTime>((ref) {
  return startOfDay(DateTime.now());
});
