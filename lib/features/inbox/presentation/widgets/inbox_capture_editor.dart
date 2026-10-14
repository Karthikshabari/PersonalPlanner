import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';

/// Shared raw-content editor for new Inbox captures and explicit capture edits.
/// The widget owns the draft until [onSubmit] completes successfully.
///
/// A capture has no date: dates are given later as sessions. [initialDueDate]
/// and the second [onSubmit] argument are kept so callers compile; the value is
/// ignored and [onSubmit] always receives null.
class InboxCaptureEditor extends StatefulWidget {
  final String initialContent;
  final String? initialDueDate;
  final Future<void> Function(String content, String? dueDate) onSubmit;
  final VoidCallback? onCommitted;
  final VoidCallback? onCancel;
  final String title;
  final bool compact;
  final bool clearOnSuccess;

  const InboxCaptureEditor({
    super.key,
    this.initialContent = '',
    this.initialDueDate,
    required this.onSubmit,
    this.onCommitted,
    this.onCancel,
    this.title = 'Add to Inbox',
    this.compact = false,
    this.clearOnSuccess = false,
  });

  @override
  State<InboxCaptureEditor> createState() => _InboxCaptureEditorState();
}

class _InboxCaptureEditorState extends State<InboxCaptureEditor> {
  late final TextEditingController _contentController;
  bool _busy = false;
  DateTime? _lastSuccessAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final content = _contentController.text;
    if (content.trim().isEmpty) {
      // A repeat click/Enter right after a successful save finds the cleared
      // field; ignore it instead of reporting a blank capture.
      final last = _lastSuccessAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 1)) {
        return;
      }
      setState(() => _error = 'Capture content must not be blank');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(content, null);
      _lastSuccessAt = DateTime.now();
      if (!mounted) return;
      if (widget.clearOnSuccess) {
        _contentController.clear();
      }
      widget.onCommitted?.call();
    } catch (error) {
      if (mounted) setState(() => _error = userFacingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final field = TextField(
      key: ValueKey(
        widget.compact ? 'inbox-quick-add' : 'inbox-capture-content',
      ),
      controller: _contentController,
      autofocus: !widget.compact,
      enabled: !_busy,
      minLines: widget.compact ? 2 : 4,
      maxLines: widget.compact ? 5 : 10,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: widget.compact ? null : 'Content',
        hintText: 'Capture a thought…',
        prefixIcon: widget.compact ? const Icon(Icons.add) : null,
        alignLabelWithHint: true,
        isDense: widget.compact,
      ),
      onSubmitted: (_) => _submit(),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.compact) ...[
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
        ],
        field,
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            key: const ValueKey('inbox-capture-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onCancel != null)
              TextButton(
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
            FilledButton(
              key: const ValueKey('inbox-capture-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.compact ? 'Add' : 'Save'),
            ),
          ],
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onCancel?.call(),
      },
      child: FocusTraversalGroup(
        child: widget.compact
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: body,
              )
            : Material(
                color: tokens.surfaceRaised,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: body,
                ),
              ),
      ),
    );
  }
}
