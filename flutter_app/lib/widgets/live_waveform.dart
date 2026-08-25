import 'dart:collection';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A live, scrolling trace of the incoming IMU signal (laryngeal axis).
/// This is DysphagiaGuard's signature visual: it makes the otherwise
/// invisible ML pipeline feel alive and connected to a real physical
/// signal, updating with every sample the ESP32 pushes to Firebase.
class LiveWaveform extends StatelessWidget {
  final Queue<double> samples;
  final Color color;
  final int maxSamples;

  const LiveWaveform({
    super.key,
    required this.samples,
    required this.color,
    this.maxSamples = 150,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(
          samples: samples.toList(),
          color: color,
          maxSamples: maxSamples,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final int maxSamples;

  _WaveformPainter({
    required this.samples,
    required this.color,
    required this.maxSamples,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // Baseline
    final baselinePaint = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), baselinePaint);

    if (samples.isEmpty) return;

    final displaySamples = samples.length > maxSamples
        ? samples.sublist(samples.length - maxSamples)
        : samples;

    final maxAbs = displaySamples.map((v) => v.abs()).fold<double>(0.001, (a, b) => a > b ? a : b);
    final scale = (size.height / 2 - 6) / maxAbs;
    final dx = size.width / (maxSamples - 1);

    final path = Path();
    final startX = size.width - (displaySamples.length - 1) * dx;

    for (var i = 0; i < displaySamples.length; i++) {
      final x = startX + i * dx;
      final y = midY - displaySamples[i] * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Glow at the leading edge (the most recent sample) — reads as "live"
    if (displaySamples.isNotEmpty) {
      final lastX = startX + (displaySamples.length - 1) * dx;
      final lastY = midY - displaySamples.last * scale;
      final glowPaint = Paint()
        ..color = color.withOpacity(0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lastX, lastY), 3.5, glowPaint);
      final haloPaint = Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(lastX, lastY), 8, haloPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
