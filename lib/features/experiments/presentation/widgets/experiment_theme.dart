import 'package:flutter/material.dart';

/// Colours used only by the Kept experiments UI. Kept apart from
/// `AppThemeTokens` so no existing token changes. This is the only file of the
/// feature that holds hex values.
@immutable
class ExperimentColors extends ThemeExtension<ExperimentColors> {
  /// Muted amber for a miss. Never red.
  final Color caution;

  /// The fill behind the "behind" chip.
  final Color cautionSoft;

  /// The planned segment of the progress track and its legend square.
  final Color planned;

  const ExperimentColors({
    required this.caution,
    required this.cautionSoft,
    required this.planned,
  });

  static const dark = ExperimentColors(
    caution: Color(0xFFE6B45A),
    cautionSoft: Color(0x26E6B45A),
    planned: Color(0x737C5CFC),
  );

  static const light = ExperimentColors(
    caution: Color(0xFFB27A0D),
    cautionSoft: Color(0x1FB27A0D),
    planned: Color(0x737C5CFC),
  );

  static ExperimentColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ExperimentColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  ExperimentColors copyWith({
    Color? caution,
    Color? cautionSoft,
    Color? planned,
  }) => ExperimentColors(
    caution: caution ?? this.caution,
    cautionSoft: cautionSoft ?? this.cautionSoft,
    planned: planned ?? this.planned,
  );

  @override
  ExperimentColors lerp(covariant ExperimentColors? other, double t) {
    if (other == null) return this;
    return ExperimentColors(
      caution: Color.lerp(caution, other.caution, t)!,
      cautionSoft: Color.lerp(cautionSoft, other.cautionSoft, t)!,
      planned: Color.lerp(planned, other.planned, t)!,
    );
  }
}
