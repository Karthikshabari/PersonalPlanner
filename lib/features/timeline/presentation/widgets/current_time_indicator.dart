import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';

class CurrentTimeIndicator extends StatefulWidget {
  final double pixelsPerMinute;

  const CurrentTimeIndicator({super.key, required this.pixelsPerMinute});

  @override
  State<CurrentTimeIndicator> createState() => _CurrentTimeIndicatorState();
}

class _CurrentTimeIndicatorState extends State<CurrentTimeIndicator> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = minutesSinceMidnight(_now) * widget.pixelsPerMinute;
    return Positioned(
      left: 0,
      right: 0,
      top: top - 0.75,
      child: IgnorePointer(
        child: Row(
          children: [
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.currentTimeIndicator,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Divider(
                color: AppColors.currentTimeIndicator,
                thickness: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
