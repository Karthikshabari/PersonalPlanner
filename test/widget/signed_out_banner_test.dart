import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/widgets/adaptive_shell.dart';
import 'package:personal_planner/features/sync/providers/runtime_backend_providers.dart';
import 'package:personal_planner/features/sync/providers/sync_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../helpers/runtime_auth_fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, Session? session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeBackendProvider.overrideWithValue(testProvisionedBackend()),
          authSessionProvider.overrideWith((ref) => Stream.value(session)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SignedOutBanner()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the banner shows while signed out', (tester) async {
    await pump(tester, null);
    expect(
      find.text('Signed out. You are seeing local-only data.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the banner is hidden while signed in', (tester) async {
    await pump(tester, testAuthSession(authUserId: authUserIdX));
    expect(find.textContaining('Signed out'), findsNothing);
  });
}
