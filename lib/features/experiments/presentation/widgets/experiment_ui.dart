import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import 'experiment_theme.dart';

/// Below this width an experiment card uses 16 padding and a 2px chart gap.
const experimentNarrowWidth = 480.0;

/// Widest the Experiments column grows on desktop.
const experimentColumnMaxWidth = 760.0;

const _tabular = [FontFeature.tabularFigures()];

/// The Experiments type scale and semantic colors, read from the active theme.
/// Every style uses tabular figures so numbers, dates and durations line up.
class ExperimentStyles {
  ExperimentStyles._(this._text, this.scheme, this.tokens, this.colors);

  factory ExperimentStyles.of(BuildContext context) {
    final theme = Theme.of(context);
    return ExperimentStyles._(
      theme.textTheme.bodyMedium ?? const TextStyle(),
      theme.colorScheme,
      AppThemeTokens.of(context),
      ExperimentColors.of(context),
    );
  }

  final TextStyle _text;
  final ColorScheme scheme;
  final AppThemeTokens tokens;
  final ExperimentColors colors;

  TextStyle _style(double size, FontWeight weight, Color color) =>
      _text.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: _tabular,
        letterSpacing: 0,
        height: null,
      );

  /// Card title: 18 semibold.
  TextStyle get cardTitle => _style(18, FontWeight.w600, scheme.onSurface);

  /// Section heading: 15 semibold.
  TextStyle get sectionHeading => _style(15, FontWeight.w600, scheme.onSurface);

  /// Body: 14 regular.
  TextStyle get body => _style(14, FontWeight.w400, scheme.onSurface);

  /// Label: 13 medium.
  TextStyle get label => _style(13, FontWeight.w500, scheme.onSurface);

  /// Caption: 12 regular, muted.
  TextStyle get caption => _style(12, FontWeight.w400, scheme.onSurfaceVariant);

  /// Stat label: 11 medium, uppercase text, 0.4 letter spacing.
  TextStyle get statLabel => _style(
    11,
    FontWeight.w500,
    scheme.onSurfaceVariant,
  ).copyWith(letterSpacing: 0.4);

  /// Stat value: 16 semibold.
  TextStyle get statValue => _style(16, FontWeight.w600, scheme.onSurface);

  /// The big "done" figure: 28 semibold.
  TextStyle get big => _style(28, FontWeight.w600, scheme.onSurface);

  /// The "done" figure with the tighter letter spacing of the Kept row.
  TextStyle get bigTight => big.copyWith(letterSpacing: -0.28);

  /// Subtitle under a Kept title: 12.5 regular, muted.
  TextStyle get subtitle =>
      _style(12.5, FontWeight.w400, scheme.onSurfaceVariant);

  /// Secondary line: 13.5 regular, muted.
  TextStyle get secondary =>
      _style(13.5, FontWeight.w400, scheme.onSurfaceVariant);

  /// Note: 13 regular, muted.
  TextStyle get note => _style(13, FontWeight.w400, scheme.onSurfaceVariant);

  /// Text link: 13 medium, muted until a color is given.
  TextStyle get link => _style(13, FontWeight.w500, scheme.onSurfaceVariant);

  /// Muted label color.
  Color get muted => scheme.onSurfaceVariant;

  /// The one accent, for fills, ticks and primary actions.
  Color get accent => scheme.primary;

  /// The accent as readable text on the card surface.
  Color get accentText => tokens.focus;

  /// Done / on track.
  Color get done => tokens.success;

  /// Behind or missed. Never red.
  Color get amber => tokens.warning;

  /// Muted amber for a miss on the Kept row. Never red.
  Color get caution => colors.caution;

  /// The fill behind a caution chip.
  Color get cautionSoft => colors.cautionSoft;

  /// The planned segment of the Kept progress track.
  Color get planned => colors.planned;

  /// The empty track behind a bar or a day column.
  Color get barTrack => scheme.onSurface.withValues(alpha: 0.09);

  /// A faint fill of [color] that keeps text on it readable.
  Color tint(Color color) => color.withValues(
    alpha: scheme.brightness == Brightness.dark ? 0.16 : 0.1,
  );

  /// The filled strip behind the Today line and inner groups.
  Color get strip => scheme.surfaceContainerHighest.withValues(alpha: 0.5);

  /// Input fill.
  Color get field => scheme.surfaceContainerHighest.withValues(alpha: 0.7);

  /// Card radius 16, inner strip and input radius 10.
  static const double cardRadius = 16;
  static const double innerRadius = 10;
}

/// A 1px hairline between major blocks of a card.
class ExperimentHairline extends StatelessWidget {
  const ExperimentHairline({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// A fully rounded label. [color] tints the fill and colors the text unless
/// [textColor] is given.
class ExperimentChip extends StatelessWidget {
  const ExperimentChip({
    super.key,
    required this.text,
    this.color,
    this.textColor,
    this.leading,
    this.fontSize = 12,
    this.fill,
  });

  final String text;
  final Color? color;
  final Color? textColor;
  final Widget? leading;
  final double fontSize;

  /// Replaces the tinted fill (for example the soft caution fill).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final base = color;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill ?? (base == null ? styles.strip : styles.tint(base)),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                text,
                style: styles.label.copyWith(
                  fontSize: fontSize,
                  color: textColor ?? base ?? styles.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 6px round dot, e.g. "running".
class ExperimentDot extends StatelessWidget {
  const ExperimentDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: ShapeDecoration(color: color, shape: const CircleBorder()),
    ),
  );
}

/// A full-width, 44 tall toggle row: [leading] on the left, a chevron on the
/// right. The icon swaps with [open]; nothing animates.
class ExperimentToggleRow extends StatelessWidget {
  const ExperimentToggleRow({
    super.key,
    required this.open,
    required this.onPressed,
    required this.leading,
  });

  final bool open;
  final VoidCallback onPressed;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: leading),
            ),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: styles.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small underlined text link, at least 44 tall. [color] defaults to the
/// muted text colour.
class ExperimentTextLink extends StatelessWidget {
  const ExperimentTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final c = color ?? styles.muted;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ExperimentStyles.innerRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(label, style: styles.link.copyWith(color: c)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
