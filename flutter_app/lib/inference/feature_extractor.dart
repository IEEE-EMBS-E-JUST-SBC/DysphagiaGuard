import 'dart:math' as math;
import '../models/imu_sample.dart';
import 'simple_fft.dart';

/// Extracts the same 8 features per IMU axis used during training in the
/// Colab notebook (mean, std, rms, peak, energy, zcr, centroid, flatness),
/// in the exact order the model expects: axis-major, feature-minor,
/// i.e. [ax_mean, ax_std, ..., ax_flatness, ay_mean, ..., gz_flatness].
///
/// This MUST stay in lockstep with feature_stats.json['feature_order'].
/// If you change the training notebook's feature set, regenerate
/// feature_stats.json and update this file to match.
class FeatureExtractor {
  final double samplingRateHz;

  const FeatureExtractor({required this.samplingRateHz});

  /// `window` is a list of IMU samples for one 3-second buffer, in
  /// chronological order. Returns 48 features (8 per channel × 6 channels).
  List<double> extract(List<ImuSample> window) {
    final channels = <String, List<double>>{
      'ax': window.map((s) => s.ax).toList(),
      'ay': window.map((s) => s.ay).toList(),
      'az': window.map((s) => s.az).toList(),
      'gx': window.map((s) => s.gx).toList(),
      'gy': window.map((s) => s.gy).toList(),
      'gz': window.map((s) => s.gz).toList(),
    };

    final features = <double>[];
    for (final axis in ['ax', 'ay', 'az', 'gx', 'gy', 'gz']) {
      final x = channels[axis]!;
      features.add(_mean(x));
      features.add(_std(x));
      features.add(_rms(x));
      features.add(_peak(x));
      features.add(_energy(x));
      features.add(_zcr(x));
      features.add(_spectralCentroid(x));
      features.add(_spectralFlatness(x));
    }
    return features;
  }

  double _mean(List<double> x) => x.reduce((a, b) => a + b) / x.length;

  double _std(List<double> x) {
    final m = _mean(x);
    final variance = x.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / x.length;
    return math.sqrt(variance);
  }

  double _rms(List<double> x) {
    final sumSq = x.map((v) => v * v).reduce((a, b) => a + b);
    return math.sqrt(sumSq / x.length);
  }

  double _peak(List<double> x) => x.map((v) => v.abs()).reduce(math.max);

  double _energy(List<double> x) {
    final sumSq = x.map((v) => v * v).reduce((a, b) => a + b);
    return sumSq / x.length;
  }

  double _zcr(List<double> x) {
    final m = _mean(x);
    final centered = x.map((v) => v - m).toList();
    var crossings = 0;
    for (var i = 0; i < centered.length - 1; i++) {
      final s1 = centered[i] >= 0 ? 1 : -1;
      final s2 = centered[i + 1] >= 0 ? 1 : -1;
      if (s1 != s2) crossings++;
    }
    return crossings / (centered.length - 1);
  }

  double _spectralCentroid(List<double> x) {
    final m = _mean(x);
    final centered = x.map((v) => v - m).toList();
    final (freqs, mags) = SimpleFFT.magnitudeSpectrum(centered, samplingRateHz);
    final magSum = mags.reduce((a, b) => a + b);
    if (magSum == 0) return 0.0;
    var weighted = 0.0;
    for (var i = 0; i < freqs.length; i++) {
      weighted += freqs[i] * mags[i];
    }
    return weighted / magSum;
  }

  double _spectralFlatness(List<double> x) {
    final m = _mean(x);
    final centered = x.map((v) => v - m).toList();
    final (_, mags) = SimpleFFT.magnitudeSpectrum(centered, samplingRateHz);
    final magsEps = mags.map((v) => v + 1e-12).toList();
    final logSum = magsEps.map((v) => math.log(v)).reduce((a, b) => a + b);
    final gMean = math.exp(logSum / magsEps.length);
    final aMean = magsEps.reduce((a, b) => a + b) / magsEps.length;
    return gMean / aMean;
  }
}
