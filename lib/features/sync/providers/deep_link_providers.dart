import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_link_source.dart';

/// App-lifetime source of incoming Planner deep links.
///
/// The app bootstrap overrides this with the single started [AppLinkSource].
/// The default is inert, so an isolated provider container (unit tests, a
/// library that is read outside a bootstrapped app) can never open a second
/// platform subscription and steal the initial link from the real one.
final appLinkSourceProvider = Provider<AppLinkSource>(
  (ref) => AppLinkSource.inert(),
);
