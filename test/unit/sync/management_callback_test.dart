import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/auth_callback.dart';
import 'package:personal_planner/core/config/management_callback.dart';

/// The two callback kinds must stay separate: a Supabase Management
/// authorization can never satisfy, mutate, or complete a Planner user Auth
/// confirmation, and the reverse.
void main() {
  test('is pinned to one non-secret destination', () {
    expect(
      ManagementCallback.redirectUrl,
      'com.personalplanner.personalplanner://management-callback',
    );
    expect(ManagementCallback.scheme, AuthCallback.scheme);
    expect(ManagementCallback.host, isNot(AuthCallback.host));
  });

  test('matches only the exact Management destination', () {
    expect(ManagementCallback.matches(ManagementCallback.redirectUrl), isTrue);
    expect(
      ManagementCallback.matches('${ManagementCallback.redirectUrl}?state=x'),
      isTrue,
      reason: 'a query is ignored rather than read: the link carries no data',
    );
    expect(
      ManagementCallback.matches(
        'com.personalplanner.personalplanner://management-callback-evil',
      ),
      isFalse,
    );
    expect(
      ManagementCallback.matches('com.personalplanner.personalplanner://other'),
      isFalse,
    );
    expect(
      ManagementCallback.matches('https://worker.test/oauth/callback'),
      isFalse,
    );
  });

  test('never accepts a Planner user Auth confirmation link', () {
    expect(ManagementCallback.matches(AuthCallback.redirectUrl), isFalse);
    expect(
      ManagementCallback.matches('${AuthCallback.redirectUrl}?code=abc'),
      isFalse,
    );
    // ...and the Planner Auth callback never accepts a Management return.
    expect(AuthCallback.tryParse(ManagementCallback.redirectUrl), isNull);
  });
}
