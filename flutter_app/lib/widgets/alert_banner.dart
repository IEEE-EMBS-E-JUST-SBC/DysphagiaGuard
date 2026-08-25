import 'package:flutter/material.dart';
import '../models/imu_sample.dart';
import '../theme/app_theme.dart';
import 'buffer_ring.dart';

/// The central status display: a color-coded classification badge inside
/// an animated buffer-fill ring, with confidence and probability bars.
/// This is the single most important glanceable element in the app.
class AlertBanner extends StatelessWidget {
  final SwallowClass swallowClass;
  final List<double> probabilities;
  final double bufferProgress;
  final bool connected;

  const AlertBanner({
    super.key,
    required this.swallowClass,
    required this.probabilities,
    required this.bufferProgress,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forSwallowClass(swallowClass);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.20), AppColors.surface, AppColors.surfaceRaised],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.32),
            blurRadius: 40,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: BufferRing(
              key: ValueKey(swallowClass),
              progress: connected ? bufferProgress : 0.0,
              color: color,
              size: 168,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconFor(swallowClass), color: color, size: 34),
                  const SizedBox(height: 10),
                  Text(
                    swallowClass.shortLabel,
                    textAlign: TextAlign.center,
                    style: AppText.statusWord.copyWith(fontSize: 20, color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ProbBar(label: 'Normal', value: _safe(probabilities, 0), color: AppColors.mint),
              _ProbBar(label: 'Delayed', value: _safe(probabilities, 1), color: AppColors.amber),
              _ProbBar(label: 'Aspiration', value: _safe(probabilities, 2), color: AppColors.coral),
            ],
          ),
        ],
      ),
    );
  }

  double _safe(List<double> p, int i) => i < p.length ? p[i] : 0.0;

  IconData _iconFor(SwallowClass c) {
    switch (c) {
      case SwallowClass.normal:
        return Icons.check_circle_rounded;
      case SwallowClass.delayedIncomplete:
        return Icons.hourglass_bottom_rounded;
      case SwallowClass.aspirationRisk:
        return Icons.warning_rounded;
      case SwallowClass.unknown:
        return Icons.sensors_off_rounded;
    }
  }
}

class _ProbBar extends StatelessWidget {
  final String label;
  final double value; // 0.0 -> 1.0
  final Color color;

  const _ProbBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${(value * 100).toStringAsFixed(0)}%', style: AppText.metricValue.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
        Container(
          width: 64,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.hairline,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withOpacity(0.6), color]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.metricLabel),
      ],
    );
  }
}
