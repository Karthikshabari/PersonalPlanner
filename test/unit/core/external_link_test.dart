import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/external_link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart'
    show PreferredLaunchMode;

import '../../helpers/fake_url_launcher.dart';

final _signUp = Uri.https('supabase.com', '/dashboard/sign-up');

Future<void> _pump(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onTap,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => onTap(context),
          child: const Text('go'),
        ),
      ),
    ),
  ),
);

void main() {
  late FakeUrlLauncher launcher;

  setUp(() {
    launcher = FakeUrlLauncher()..install();
    resetExternalLinkGuard();
  });

  group('launchExternalUri', () {
    test('opens an https address in the external application', () async {
      expect(await launchExternalUri(_signUp), isTrue);
      expect(launcher.launched, <String>[_signUp.toString()]);
      expect(
        launcher.options.single.mode,
        PreferredLaunchMode.externalApplication,
      );
      expect(
        launcher.canLaunchCalls,
        0,
        reason: 'must not gate on canLaunchUrl',
      );
    });

    test('returns false when the platform declines', () async {
      launcher.result = false;
      expect(await launchExternalUri(_signUp), isFalse);
    });

    test('returns false instead of throwing', () async {
      launcher.error = Exception('no browser');
      expect(await launchExternalUri(_signUp), isFalse);
    });

    test('rejects every scheme but https without launching', () async {
      for (final raw in <String>[
        'http://supabase.com/',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'mailto:a@b.c',
        'planner://auth',
        'https:///no-host',
      ]) {
        expect(await launchExternalUri(Uri.parse(raw)), isFalse, reason: raw);
      }
      expect(launcher.launched, isEmpty);
    });

    test('a host check can narrow the allowed addresses', () async {
      for (final raw in <String>[
        'https://supabase.com.evil.example/',
        'https://evilsupabase.com/',
        'https://example.com/',
        'https://karthikshabri.dev/',
      ]) {
        expect(
          await launchExternalUri(Uri.parse(raw), allowed: isSupabaseUri),
          isFalse,
          reason: raw,
        );
      }
      expect(launcher.launched, isEmpty);
      for (final raw in <String>[
        'https://supabase.com/dashboard/sign-up',
        'https://api.supabase.com/v1/oauth/authorize',
      ]) {
        expect(
          await launchExternalUri(Uri.parse(raw), allowed: isSupabaseUri),
          isTrue,
          reason: raw,
        );
      }
    });

    test('a second tap on the same address opens one window', () async {
      final results = await Future.wait(<Future<bool>>[
        launchExternalUri(_signUp),
        launchExternalUri(_signUp),
      ]);
      expect(results, <bool>[true, true]);
      expect(await launchExternalUri(_signUp), isTrue);
      expect(launcher.launched, hasLength(1));
    });

    test('a failed launch can be retried at once', () async {
      launcher.result = false;
      expect(await launchExternalUri(_signUp), isFalse);
      launcher.result = true;
      expect(await launchExternalUri(_signUp), isTrue);
      expect(launcher.launched, hasLength(2));
    });
  });

  group('openExternalLink', () {
    testWidgets('shows nothing when the browser opens', (tester) async {
      await _pump(tester, (context) => openExternalLink(context, _signUp));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(launcher.launched, <String>[_signUp.toString()]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('shows the address with Copy when launch returns false', (
      tester,
    ) async {
      launcher.result = false;
      await _pump(tester, (context) => openExternalLink(context, _signUp));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.textContaining(_signUp.toString()), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('shows the fallback when launch throws, and Copy copies', (
      tester,
    ) async {
      launcher.error = PlatformException(code: 'boom');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, (context) => openExternalLink(context, _signUp));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, _signUp.toString());
    });

    testWidgets('a rejected scheme shows the fallback and launches nothing', (
      tester,
    ) async {
      final plain = Uri.parse('http://supabase.com/');
      await _pump(tester, (context) => openExternalLink(context, plain));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(launcher.launched, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('does not touch a disposed context', (tester) async {
      launcher.result = false;
      await _pump(tester, (context) => openExternalLink(context, _signUp));
      await tester.tap(find.text('go'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('long addresses are shortened in the message only', (
      tester,
    ) async {
      launcher.result = false;
      final long = Uri.https('api.supabase.com', '/v1/oauth/authorize', {
        'state': 'x' * 400,
      });
      await _pump(tester, (context) => openExternalLink(context, long));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(long.toString()), findsNothing);
      expect(find.textContaining('…'), findsOneWidget);
    });
  });
}
