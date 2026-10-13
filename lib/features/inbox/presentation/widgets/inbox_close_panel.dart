import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../task_editor/presentation/widgets/tag_field.dart';
import '../../domain/inbox_history.dart';
import '../../providers/inbox_provider.dart';

/// The reason limit in UTF-16 units. The repository counts code points, which
/// is never more, so a text that fits here is always accepted.
const inboxReasonMaxUnits = InboxHistory.maxReasonLength;

/// The counter appears from this many units on.
const _counterFromUnits = 180;

/// A readable line for an error thrown by the Inbox repository.
String inboxErrorText(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '')
    .replaceFirst('Invalid argument: ', '');

/// The inline panel behind "Close it" and "Let go". Reasons are typed text
/// only: no chips, no suggestions. Close it stays disabled until the trimmed
/// text is not empty; Let go takes an optional reason.
class InboxClosePanel extends ConsumerStatefulWidget {
  const InboxClosePanel({
    super.key,
    required this.itemId,
    required this.letGo,
    required this.onClosed,
    required this.onCancel,
  });

  final String itemId;

  /// True for Let go (optional reason), false for Close it (required reason).
  final bool letGo;

  /// Called after the repository accepted the write.
  final VoidCallback onClosed;
  final VoidCallback onCancel;

  @override
  ConsumerState<InboxClosePanel> createState() => _InboxClosePanelState();
}

class _InboxClosePanelState extends ConsumerState<InboxClosePanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'inbox-reason');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // Pressing the footer button left the focus on a control that has just
    // gone, so `autofocus` alone would not take it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && (widget.letGo || _controller.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final text = _controller.text.trim();
    final repository = ref.read(inboxRepositoryProvider);
    final now = ref.read(inboxNowFactoryProvider)();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.letGo) {
        await repository.letGo(widget.itemId, text.isEmpty ? null : text, now);
      } else {
        await repository.closeItem(widget.itemId, text, now);
      }
      if (!mounted) return;
      showAppToast(
        context,
        widget.letGo
            ? 'Let go. Moved to Dropped.'
            : 'Closed. Moved to Dropped.',
      );
      widget.onClosed();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = inboxErrorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = _controller.text.length;
    final action = widget.letGo ? 'Let go' : 'Close it';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Column(
        key: ValueKey(
          widget.letGo ? 'inbox-let-go-panel' : 'inbox-close-panel',
        ),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('inbox-reason-field'),
            controller: _controller,
            focusNode: _focus,
            enabled: !_busy,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            inputFormatters: const [
              Utf16LengthLimitingTextInputFormatter(inboxReasonMaxUnits),
            ],
            decoration: InputDecoration(
              labelText: widget.letGo
                  ? 'Reason (optional)'
                  : 'Why are you closing it?',
              hintText: widget.letGo ? null : 'Type a reason',
              helperText: widget.letGo
                  ? null
                  : 'Sessions not started yet are removed from Day. '
                        'Missed ones stay in Review.',
              helperMaxLines: 2,
              counterText: units >= _counterFromUnits
                  ? '$units/$inboxReasonMaxUnits'
                  : '',
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              key: const ValueKey('inbox-panel-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton(
                key: const ValueKey('inbox-panel-cancel'),
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('inbox-panel-submit'),
                onPressed: _canSubmit ? _submit : null,
                child: Text(action),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
