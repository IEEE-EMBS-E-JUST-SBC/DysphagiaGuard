import 'dart:math' as math;
import '../models/imu_sample.dart';

/// Zero-offset + noise-floor baseline captured during the 30s calibration
/// window, while the device is at rest on the neck.
class GyroCalibration {
  final double gxBias, gyBias, gzBias;
  final double azBias;
  final double gyroNoiseFloor; // std of |gyro| magnitude at rest
  final double azNoiseFloor; // std of az at rest
  final DateTime capturedAt;

  const GyroCalibration({
    required this.gxBias,
    required this.gyBias,
    required this.gzBias,
    required this.azBias,
    required this.gyroNoiseFloor,
    required this.azNoiseFloor,
    required this.capturedAt,
  });

  /// Bias-corrected gyro magnitude for one sample.
  double gyroMag(ImuSample s) {
    final gx = s.gx - gxBias;
    final gy = s.gy - gyBias;
    final gz = s.gz - gzBias;
    return math.sqrt(gx * gx + gy * gy + gz * gz);
  }

  double azCorrected(ImuSample s) => s.az - azBias;
}

/// Builds a [GyroCalibration] from ~30s of resting samples.
class CalibrationCollector {
  final List<ImuSample> _samples = [];
  final Duration duration;
  DateTime? _startedAt;

  CalibrationCollector({this.duration = const Duration(seconds: 30)});

  void start() => _startedAt = DateTime.now();

  bool get isRunning => _startedAt != null && !isComplete;

  double get progress {
    if (_startedAt == null) return 0.0;
    final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
    return (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get isComplete =>
      _startedAt != null &&
      DateTime.now().difference(_startedAt!) >= duration;

  void addSample(ImuSample s) {
    if (_startedAt == null || isComplete) return;
    _samples.add(s);
  }

  /// Null if not enough samples were captured (e.g. feed dropped out).
  GyroCalibration? finalize() {
    if (_samples.length < 20) return null;

    double mean(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    double std(Iterable<double> xs, double m) {
      final vals = xs.toList();
      final variance = vals.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / vals.length;
      return math.sqrt(variance);
    }

    final gxBias = mean(_samples.map((s) => s.gx));
    final gyBias = mean(_samples.map((s) => s.gy));
    final gzBias = mean(_samples.map((s) => s.gz));
    final azBias = mean(_samples.map((s) => s.az));

    final gyroMags = _samples.map((s) {
      final gx = s.gx - gxBias, gy = s.gy - gyBias, gz = s.gz - gzBias;
      return math.sqrt(gx * gx + gy * gy + gz * gz);
    });
    final gyroNoiseFloor = math.max(std(gyroMags, mean(gyroMags)), 0.5);

    final azVals = _samples.map((s) => s.az - azBias);
    final azNoiseFloor = math.max(std(azVals, mean(azVals)), 0.01);

    return GyroCalibration(
      gxBias: gxBias,
      gyBias: gyBias,
      gzBias: gzBias,
      azBias: azBias,
      gyroNoiseFloor: gyroNoiseFloor,
      azNoiseFloor: azNoiseFloor,
      capturedAt: DateTime.now(),
    );
  }
}

/// Rule-based swallow event classifier.
///
/// Replaces the on-device TFLite model's decision-making. The TFLite
/// interpreter (see SwallowClassifier) is still loaded so the model asset
/// and inference path stay wired up, but its output is not used to make
/// the call — this heuristic pipeline classifies instead, driven by the
/// gyro-magnitude + accelerometer-az pattern within an already-buffered
/// window, using the per-device baseline captured during calibration.
///
/// This is intentionally simple and inspectable rather than a black box:
/// each threshold below corresponds to a physically meaningful trait of
/// the motion signature (how big the motion was, how long it lasted, how
/// cleanly it settled back to baseline, and whether a second spike
/// followed shortly after — a pattern associated with a cough/clearing
/// reflex after aspiration).
class HeuristicSwallowClassifier {
  final GyroCalibration calibration;
  final double samplingRateHz;

  const HeuristicSwallowClassifier({
    required this.calibration,
    required this.samplingRateHz,
  });

  ClassificationResult classify(List<ImuSample> window) {
    if (window.isEmpty) {
      return ClassificationResult(
        swallowClass: SwallowClass.unknown,
        probabilities: const [0.0, 0.0, 0.0],
        timestamp: DateTime.now(),
      );
    }

    final gyroMags = window.map(calibration.gyroMag).toList();
    final azVals = window.map(calibration.azCorrected).toList();

    final threshold = calibration.gyroNoiseFloor * 3.5;

    final peakMag = gyroMags.reduce(math.max);
    final peakIdx = gyroMags.indexOf(peakMag);
    final timeToPeakS = peakIdx / samplingRateHz;

    // Duration the signal stayed above threshold (event "width").
    final aboveThreshold = gyroMags.where((v) => v > threshold).length;
    final eventDurationS = aboveThreshold / samplingRateHz;

    // Settle: how long after the peak it takes to drop back near baseline.
    var settleIdx = gyroMags.length - 1;
    for (var i = peakIdx; i < gyroMags.length; i++) {
      if (gyroMags[i] < calibration.gyroNoiseFloor * 1.5) {
        settleIdx = i;
        break;
      }
    }
    final settleTimeS = (settleIdx - peakIdx) / samplingRateHz;

    // Secondary spike after the main peak — possible cough/clearing motion.
    var secondarySpike = false;
    if (settleIdx < gyroMags.length - 5) {
      final tail = gyroMags.sublist(settleIdx);
      final tailPeak = tail.reduce(math.max);
      if (tailPeak > threshold * 0.8) secondarySpike = true;
    }

    // az excursion adds confidence that this was a real laryngeal-elevation
    // event rather than incidental head/neck motion.
    final azExcursion = azVals.map((v) => v.abs()).reduce(math.max);
    final hasAzSignature = azExcursion > calibration.azNoiseFloor * 3.0;

    if (peakMag < threshold || !hasAzSignature) {
      // No clear motion event in this window.
      return ClassificationResult(
        swallowClass: SwallowClass.unknown,
        probabilities: const [0.0, 0.0, 0.0],
        timestamp: DateTime.now(),
      );
    }

    // --- Rule set ---
    // Aspiration-risk: irregular pattern — secondary spike (cough-like)
    // shortly after the main swallow motion, or an unusually sharp/high
    // peak paired with a slow settle (uncoordinated motion).
    if (secondarySpike || (peakMag > threshold * 2.5 && settleTimeS > 1.2)) {
      final conf = _confidenceFrom(peakMag, threshold, extra: secondarySpike ? 0.15 : 0.0);
      return ClassificationResult(
        swallowClass: SwallowClass.aspirationRisk,
        probabilities: [1 - conf - 0.05, 0.05, conf],
        timestamp: DateTime.now(),
      );
    }

    // Delayed/incomplete: motion took a while to settle, or the whole
    // event ran unusually long relative to a normal fast swallow.
    if (settleTimeS > 0.7 || eventDurationS > 1.0 || timeToPeakS > 0.6) {
      final conf = _confidenceFrom(settleTimeS, 0.7, scale: 0.4);
      return ClassificationResult(
        swallowClass: SwallowClass.delayedIncomplete,
        probabilities: [0.1, conf, 1 - conf - 0.1],
        timestamp: DateTime.now(),
      );
    }

    // Normal: brisk peak, short duration, clean settle.
    final conf = _confidenceFrom(threshold * 2 - peakMag.clamp(0, threshold * 2), 0, scale: 0.3)
        .clamp(0.55, 0.95);
    return ClassificationResult(
      swallowClass: SwallowClass.normal,
      probabilities: [conf, (1 - conf) * 0.7, (1 - conf) * 0.3],
      timestamp: DateTime.now(),
    );
  }

  /// Maps a raw signal margin into a 0.55-0.95 pseudo-confidence so the UI's
  /// probability bars stay meaningful without pretending to be a trained
  /// model's softmax output.
  double _confidenceFrom(double value, double reference, {double scale = 0.3, double extra = 0.0}) {
    final margin = (value - reference).abs() / (reference.abs() + 1.0);
    final base = 0.55 + (margin * scale).clamp(0.0, 0.4);
    return (base + extra).clamp(0.55, 0.95);
  }
}
