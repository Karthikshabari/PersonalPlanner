import 'package:flutter/material.dart';

/// 1–5 star rating used by the review forms (energy, productivity,
/// planning accuracy, overall). Tapping the selected star clears it.
class RatingPicker extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const RatingPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: 0,
      children: [
        SizedBox(
          width: 170,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        for (var star = 1; star <= 5; star++)
          IconButton(
            key: ValueKey('rating-$label-$star'),
            tooltip: '$star',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              star <= (value ?? 0) ? Icons.star : Icons.star_border,
              color: star <= (value ?? 0)
                  ? Theme.of(context).colorScheme.secondary
                  : null,
            ),
            onPressed: () =>
                onChanged(value == star ? null : star),
          ),
        if (value != null)
          Text('$value/5',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
