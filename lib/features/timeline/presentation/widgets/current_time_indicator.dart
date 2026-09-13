import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/planner_day_axis.dart';
import '../../../../core/utils/planner_time_zone.dart';

class CurrentTimeIndicator extends StatefulWidget {
  final double pixelsPerMinute;
  final DateTime day;
  final DateTime? now;

  /// Horizontal bounds within the containing timeline stack.
  ///
  /// The default keeps the indicator scoped to a single day column. Week
  /// pages override these bounds so the same indicator can span every
  /// displayed day without changing its time calculation.
  final double left;
  final double right;

  const CurrentTimeIndicator({
    super.key,
    required this.pixelsPerMinute,
    required this.day,
    this.now,
    this.left = 0,
    this.right = 0,
  });

  @override
  State<CurrentTimeIndicator> createState() => _CurrentTimeIndicatorState();
}

class _CurrentTimeIndicatorState extends State<CurrentTimeIndicator> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTickerIfNeeded();
  }

  void _startTickerIfNeeded() {
    if (widget.now != null) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant CurrentTimeIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.now == null) == (widget.now == null)) return;
    _timer?.cancel();
    _timer = null;
    _now = DateTime.now();
    _startTickerIfNeeded();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final effectiveNow = widget.now ?? _now;
    final local = PlannerTimeZone.toPlannerLocal(effectiveNow);
    final top =
        PlannerDayAxis(widget.day).elapsedMinutes(effectiveNow) *
        widget.pixelsPerMinute;
    return Positioned(
      left: widget.left,
      right: widget.right,
      top: top - 0.75,
      child: IgnorePointer(
        child: Semantics(
          label:
              'Current time ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
          child: Row(
            children: [
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tokens.info,
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                ),
                child: Text(
                  '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: tokens.surfaceRaised,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: Divider(color: tokens.info, thickness: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}
