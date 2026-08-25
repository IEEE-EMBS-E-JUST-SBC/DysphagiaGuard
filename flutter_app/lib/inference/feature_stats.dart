import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Metadata + normalization stats exported alongside the TFLite model by
/// the training notebook (feature_stats.json). Loaded once at startup.
class FeatureStats {
  final List<String> classNames;
  final List<String> imuChannels;
  final double samplingRateHz;
  final double windowSeconds;
  final int windowSamples;
  final List<String> featureOrder;
  final List<double> scalerMean;
  final List<double> scalerScale;

  const FeatureStats({
    required this.classNames,
    required this.imuChannels,
    required this.samplingRateHz,
    required this.windowSeconds,
    required this.windowSamples,
    required this.featureOrder,
    required this.scalerMean,
    required this.scalerScale,
  });

  static Future<FeatureStats> loadFromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    List<double> asDoubleList(dynamic v) =>
        (v as List).map((e) => (e as num).toDouble()).toList();
    List<String> asStringList(dynamic v) =>
        (v as List).map((e) => e as String).toList();

    return FeatureStats(
      classNames: asStringList(json['class_names']),
      imuChannels: asStringList(json['imu_channels']),
      samplingRateHz: (json['sampling_rate_hz'] as num).toDouble(),
      windowSeconds: (json['window_seconds'] as num).toDouble(),
      windowSamples: (json['window_samples'] as num).toInt(),
      featureOrder: asStringList(json['feature_order']),
      scalerMean: asDoubleList(json['scaler_mean']),
      scalerScale: asDoubleList(json['scaler_scale']),
    );
  }

  /// Applies (x - mean) / scale elementwise, matching sklearn's
  /// StandardScaler.transform used during training.
  List<double> normalize(List<double> rawFeatures) {
    assert(rawFeatures.length == scalerMean.length);
    return List<double>.generate(
      rawFeatures.length,
      (i) => (rawFeatures[i] - scalerMean[i]) / scalerScale[i],
    );
  }
}
