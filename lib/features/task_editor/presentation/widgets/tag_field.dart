import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/daos/tag_dao.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../data/tag_repository.dart';
import '../../providers/tag_providers.dart';

/// The longest tag name, counted in UTF-16 code units like the `tags.name`
/// column (`withLength(1..100)`, ED9).
const maxTagNameUnits = 100;

/// Keeps a text within [maxUnits] UTF-16 code units without ever splitting a
/// grapheme cluster (an emoji stays whole or is dropped). Flutter's
/// `maxLength` counts grapheme clusters instead, which would let an emoji
/// sequence exceed a limit that is counted in code units (ED9).
class Utf16LengthLimitingTextInputFormatter extends TextInputFormatter {
  const Utf16LengthLimitingTextInputFormatter(this.maxUnits);

  final int maxUnits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxUnits) return newValue;
    final kept = StringBuffer();
    var units = 0;
    for (final cluster in newValue.text.characters) {
      if (units + cluster.length > maxUnits) break;
      kept.write(cluster);
      units += cluster.length;
    }
    final text = kept.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// One entry of the option list: an existing tag or the "create" row.
class _TagChoice {
  const _TagChoice.existing(TagOptionRow this.option) : createName = null;
  const _TagChoice.create(String this.createName) : option = null;

  final TagOptionRow? option;
  final String? createName;

  String get text => option?.name ?? createName!;
}

/// Optional tag of a block: an autocomplete text field (ED17).
///
/// The field's value follows its text at every change, not on focus loss: a
/// text whose [TagRepository.normalizeTagKey] matches an active tag selects
/// that tag, other text is a pending new tag, empty text clears the tag.
/// [onChanged] receives the selected tag id and the pending new name; either
/// may be null. A change that comes from outside (a new [selectedTagId] or
/// [pendingName]) replaces the text without calling [onChanged].
class TagField extends ConsumerStatefulWidget {
  const TagField({
    super.key,
    required this.selectedTagId,
    required this.pendingName,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selectedTagId;
  final String? pendingName;
  final bool enabled;
  final void Function(String? tagId, String? pendingName) onChanged;

  @override
  ConsumerState<TagField> createState() => _TagFieldState();
}

class _TagFieldState extends ConsumerState<TagField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// The value the field currently stands for, so a rebuild with the same
  /// values is not mistaken for a change from outside.
  String? _knownId;
  String? _knownPending;

  /// True while the text still has to be filled from the tag's stored name
  /// because the option list had not arrived yet.
  bool _awaitingName = false;

  /// Scrolling that follows typing or focus (the field revealing its own
  /// caret) must not close the suggestions; only a later scroll does.
  DateTime _scrollGraceUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void _startScrollGrace() =>
      _scrollGraceUntil = DateTime.now().add(const Duration(milliseconds: 600));

  /// A context under the autocomplete's own `Actions`; the suggestions
  /// overlay is not, so it dismisses itself through this one.
  BuildContext? _fieldContext;

  void _closeSuggestionsOnScroll() {
    final fieldContext = _fieldContext;
    if (!DateTime.now().isAfter(_scrollGraceUntil) ||
        fieldContext == null ||
        !fieldContext.mounted) {
      return;
    }
    Actions.maybeInvoke(fieldContext, const DismissIntent());
  }

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    _knownId = _blankToNull(widget.selectedTagId);
    _knownPending = _blankToNull(widget.pendingName);
    ref.listenManual<AsyncValue<List<TagOptionRow>>>(tagOptionsProvider, (
      previous,
      next,
    ) {
      if (_awaitingName && next.hasValue) _applyKnownValueToText();
    }, fireImmediately: true);
    _applyKnownValueToText();
  }

  @override
  void didUpdateWidget(TagField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = _blankToNull(widget.selectedTagId);
    final pending = _blankToNull(widget.pendingName);
    if (id != _knownId || pending != _knownPending) {
      _knownId = id;
      _knownPending = pending;
      _applyKnownValueToText();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<TagOptionRow> get _options =>
      ref.read(tagOptionsProvider).asData?.value ?? const [];

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      // An empty field keeps the default invalid selection so that the first
      // tap changes the controller and opens the option list; RawAutocomplete
      // computes its options only when the controller value changes.
      selection: text.isEmpty
          ? const TextSelection.collapsed(offset: -1)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  /// Fills the text from the known value without calling [onChanged].
  void _applyKnownValueToText() {
    final pending = _knownPending;
    final id = _knownId;
    if (pending != null) {
      _awaitingName = false;
      _setText(pending);
    } else if (id == null) {
      _awaitingName = false;
      _setText('');
    } else {
      TagOptionRow? match;
      for (final option in _options) {
        if (option.id == id) match = option;
      }
      if (match != null) {
        _awaitingName = false;
        _setText(match.name);
      } else {
        // Keep the text as it is until the list has this tag.
        _awaitingName = true;
      }
    }
  }

  /// Once the user leaves the field, show a matched tag under its stored
  /// spelling ("learn c" becomes "Learn C").
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _startScrollGrace();
      return;
    }
    final id = _knownId;
    if (id == null) return;
    for (final option in _options) {
      if (option.id == id && _controller.text != option.name) {
        _setText(option.name);
      }
    }
  }

  TagOptionRow? _matchFor(String text) {
    final key = TagRepository.normalizeTagKey(text);
    if (key.isEmpty) return null;
    TagOptionRow? best;
    for (final option in _options) {
      if (TagRepository.normalizeTagKey(option.name) != key) continue;
      if (best == null ||
          option.createdAt.compareTo(best.createdAt) < 0 ||
          (option.createdAt == best.createdAt &&
              option.id.compareTo(best.id) < 0)) {
        best = option;
      }
    }
    return best;
  }

  void _report(String? id, String? pending) {
    setState(() {
      _knownId = id;
      _knownPending = pending;
    });
    widget.onChanged(id, pending);
  }

  void _onTextChanged(String text) {
    _startScrollGrace();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _report(null, null);
      return;
    }
    final match = _matchFor(text);
    if (match != null) {
      _report(match.id, null);
    } else {
      _report(null, trimmed);
    }
  }

  void _onSelected(_TagChoice choice) {
    final option = choice.option;
    if (option != null) {
      _report(option.id, null);
    } else {
      _report(null, choice.createName!.trim());
    }
  }

  void _clear() {
    _setText('');
    _report(null, null);
  }

  Iterable<_TagChoice> _choicesFor(String text) {
    final key = TagRepository.normalizeTagKey(text);
    final choices = <_TagChoice>[
      for (final option in _options)
        if (key.isEmpty ||
            TagRepository.normalizeTagKey(option.name).contains(key))
          _TagChoice.existing(option),
    ];
    if (key.isNotEmpty && _matchFor(text) == null) {
      choices.add(_TagChoice.create(text.trim()));
    }
    return choices;
  }

  @override
  Widget build(BuildContext context) {
    final optionsAsync = ref.watch(tagOptionsProvider);
    if (optionsAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(optionsAsync.error!),
        onRetry: () => ref.invalidate(tagOptionsProvider),
        compact: true,
      );
    }
    if (!optionsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasValue = _knownId != null || _knownPending != null;
    // The suggestions float in the app overlay, not inside the editor's
    // scroll view, so they cannot scroll or clip with the field. They close
    // when that scroll view scrolls instead of being left behind.
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    return RawAutocomplete<_TagChoice>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      displayStringForOption: (choice) => choice.text,
      optionsBuilder: (value) => _choicesFor(value.text),
      onSelected: _onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Builder(
          builder: (fieldContext) {
            _fieldContext = fieldContext;
            return TextField(
              key: const ValueKey('task-tag-field'),
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              inputFormatters: const [
                Utf16LengthLimitingTextInputFormatter(maxTagNameUnits),
              ],
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                labelText: 'Tag',
                helperText: _knownPending != null
                    ? 'A new tag is created when you save.'
                    : null,
                suffixIcon: hasValue && widget.enabled
                    ? IconButton(
                        key: const ValueKey('task-tag-clear'),
                        tooltip: 'Clear tag',
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      )
                    : null,
              ),
            );
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final choices = options.toList(growable: false);
        final tokens = AppThemeTokens.of(context);
        final highlighted = AutocompleteHighlightedOption.of(context);
        // The list opens below the field; keep it within the screen.
        final media = MediaQuery.of(context);
        final fieldBox = _fieldContext?.findRenderObject();
        final below = fieldBox is RenderBox && fieldBox.attached
            ? media.size.height -
                  media.viewInsets.bottom -
                  fieldBox.localToGlobal(Offset(0, fieldBox.size.height)).dy -
                  AppSpacing.sm
            : 240.0;
        final maxHeight = below.clamp(56.0, 240.0);
        return _CloseOnScroll(
          position: scrollPosition,
          onScroll: _closeSuggestionsOnScroll,
          child: Material(
            elevation: 4,
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  return _TagOptionTile(
                    choice: choice,
                    highlighted: index == highlighted,
                    onTap: () => onSelected(choice),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Calls [onScroll] when [position] scrolls. Lives only while the suggestions
/// are shown, so [onScroll] only ever closes an open list.
class _CloseOnScroll extends StatefulWidget {
  const _CloseOnScroll({
    required this.position,
    required this.onScroll,
    required this.child,
  });

  final ScrollPosition? position;
  final VoidCallback onScroll;
  final Widget child;

  @override
  State<_CloseOnScroll> createState() => _CloseOnScrollState();
}

class _CloseOnScrollState extends State<_CloseOnScroll> {
  double? _lastPixels;

  @override
  void initState() {
    super.initState();
    _lastPixels = widget.position?.pixels;
    widget.position?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_CloseOnScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position?.removeListener(_onScroll);
      _lastPixels = widget.position?.pixels;
      widget.position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pixels = widget.position?.pixels;
    if (pixels == null || pixels == _lastPixels) return;
    _lastPixels = pixels;
    if (mounted) widget.onScroll();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TagOptionTile extends StatelessWidget {
  const _TagOptionTile({
    required this.choice,
    required this.highlighted,
    required this.onTap,
  });

  final _TagChoice choice;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final option = choice.option;
    final label = option == null ? 'Create tag "${choice.text}"' : option.name;
    return InkWell(
      key: ValueKey(
        option == null ? 'tag-option-create' : 'tag-option-${option.id}',
      ),
      onTap: onTap,
      child: Container(
        color: highlighted ? tokens.selected : null,
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (option != null && option.hasExperiment) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.science_outlined,
                size: 16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Experiment',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
