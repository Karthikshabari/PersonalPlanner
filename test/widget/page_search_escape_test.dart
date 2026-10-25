import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/search/page_search.dart';
import 'package:personal_planner/features/timeline/presentation/providers/timeline_action_provider.dart';
import 'package:personal_planner/platform/desktop/keyboard_shortcuts.dart';

const _field = ValueKey('page-search-field');
final _outside = FocusNode(debugLabel: 'outside-page');

class _Probe extends StatelessWidget {
  const _Probe({this.scoped = true});

  final bool scoped;

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(title: const PageSearchTitle('Probe')),
      body: const Text('probe body'),
    );
    return scoped
        ? PageSearchScope(hint: 'Search probe', child: scaffold)
        : scaffold;
  }
}

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      builder: (context, child) => KeyboardShortcutHandler(
        // A focus target outside any page, like the canvas behind the shell.
        child: Column(
          children: [
            Focus(focusNode: _outside, child: const SizedBox(height: 1)),
            Expanded(child: child!),
          ],
        ),
      ),
      home: const Scaffold(body: Text('base')),
    ),
  );
}

Future<void> _pushProbe(WidgetTester tester, {bool scoped = true}) async {
  // Like the app's shell: the page sits in a nested navigator, so a dialog on
  // the root navigator does not make the page's route non-current.
  appNavigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Navigator(
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => _Probe(scoped: scoped)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PageSearchController _controller(WidgetTester tester) =>
    PageSearchScope.maybeOf(tester.element(find.text('probe body')))!;

int _cancelRequests(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.text('probe body')))
        .read(timelineCancelRequestProvider);

Future<void> _esc(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// [testWidgets] on Linux, so the desktop shortcuts are active.
void _desktopTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _desktopTest('Esc closes an open page search after focus left the page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester);
    final controller = _controller(tester)..open();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_field), 'plan');
    await tester.pump();

    _outside.requestFocus();
    await tester.pump();
    expect(controller.focusNode.hasFocus, isFalse);
    expect(controller.isOpen.value, isTrue);

    await _esc(tester);

    expect(controller.isOpen.value, isFalse);
    expect(find.byKey(_field), findsNothing);
  });

  _desktopTest('Esc inside the field closes once, global escape stays out', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester);
    final controller = _controller(tester)..open();
    await tester.pumpAndSettle();
    expect(controller.focusNode.hasFocus, isTrue);
    final before = _cancelRequests(tester);

    await _esc(tester);

    expect(controller.isOpen.value, isFalse);
    expect(_cancelRequests(tester), before);
  });

  _desktopTest('search closed: Esc still runs the global escape', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester);
    final controller = _controller(tester);
    final before = _cancelRequests(tester);

    await _esc(tester);

    expect(controller.isOpen.value, isFalse);
    expect(_cancelRequests(tester), before + 1);
  });

  // Today the planner's own Esc binding consumes the key above a dialog, so
  // Esc does not dismiss the dialog itself; that is unchanged here. What this
  // fix owes is that page search stays open while a dialog has focus.
  _desktopTest('dialog on top: Esc leaves page search open', (tester) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester);
    final controller = _controller(tester)..open();
    await tester.pumpAndSettle();
    showDialog<void>(
      context: appNavigatorKey.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(content: Text('dialog body')),
    );
    await tester.pumpAndSettle();
    expect(find.text('dialog body'), findsOneWidget);
    final before = _cancelRequests(tester);

    await _esc(tester);

    expect(controller.isOpen.value, isTrue);
    expect(_cancelRequests(tester), before + 1);

    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('dialog body'), findsNothing);
    expect(controller.isOpen.value, isTrue);

    await _esc(tester);

    expect(controller.isOpen.value, isFalse);
  });

  _desktopTest('unscoped page: Esc runs the global escape as before', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, scoped: false);
    final before = _cancelRequests(tester);

    await _esc(tester);

    expect(_cancelRequests(tester), before + 1);
  });
}
