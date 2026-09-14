import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/platform/desktop/keyboard_shortcuts.dart';

class _KeyboardEditingProbe extends StatefulWidget {
  const _KeyboardEditingProbe();

  @override
  State<_KeyboardEditingProbe> createState() => _KeyboardEditingProbeState();
}

class _KeyboardEditingProbeState extends State<_KeyboardEditingProbe> {
  final singleController = TextEditingController();
  final multilineController = TextEditingController();
  var submits = 0;

  @override
  void dispose() {
    singleController.dispose();
    multilineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              key: const ValueKey('shortcut-single-line'),
              controller: singleController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => setState(() => submits++),
            ),
            TextField(
              key: const ValueKey('shortcut-multiline'),
              controller: multilineController,
              minLines: 2,
              maxLines: null,
              textInputAction: TextInputAction.newline,
            ),
            Text('submits: $submits'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'global planner shortcuts yield editing keys to focused text fields',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              navigatorKey: appNavigatorKey,
              home: const KeyboardShortcutHandler(
                child: _KeyboardEditingProbe(),
              ),
            ),
          ),
        );

        final single = find.byKey(const ValueKey('shortcut-single-line'));
        final multiline = find.byKey(const ValueKey('shortcut-multiline'));
        final singleController = tester.widget<TextField>(single).controller!;
        final multilineController = tester
            .widget<TextField>(multiline)
            .controller!;

        await tester.tap(single);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'abc',
            selection: TextSelection.collapsed(offset: 3),
          ),
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(singleController.text, 'ab');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(singleController.text, isEmpty);

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'abcd',
            selection: TextSelection.collapsed(offset: 4),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(
          singleController.selection,
          const TextSelection.collapsed(offset: 3),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();
        expect(singleController.text, 'abc');

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'select me',
            selection: TextSelection.collapsed(offset: 9),
          ),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          singleController.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );

        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
        await tester.pump();
        expect(singleController.text, 'select me');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('submits: 1'), findsOneWidget);

        await tester.tap(multiline);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'line one',
            selection: TextSelection.collapsed(offset: 8),
          ),
        );
        await tester.pump();
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
        await tester.pump();
        expect(multilineController.text, 'line one');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'line one\n',
            selection: TextSelection.collapsed(offset: 9),
          ),
        );
        await tester.pump();
        expect(multilineController.text, 'line one\n');

        expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
        await tester.pump();

        await tester.tap(find.text('submits: 1'));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('shortcut-help-dialog')),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
