import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/imu_sample.dart';
import '../theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color? accent;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.cyan;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.glassCard(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: AppText.metricLabel, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: AppText.metricValue.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: AppText.caption),
        ],
      ),
    );
  }
}

/// A single row in the scrollable event history log.
class EventHistoryTile extends StatelessWidget {
  final ClassificationResult result;

  const EventHistoryTile({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forSwallowClass(result.swallowClass);
    final time = DateFormat.Hms().format(result.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.14), AppColors.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, spreadRadius: -6),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.7), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              result.swallowClass.label,
              style: AppText.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${(result.confidence * 100).toStringAsFixed(0)}%',
              style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(time, style: AppText.caption),
        ],
      ),
    );
  }
}
