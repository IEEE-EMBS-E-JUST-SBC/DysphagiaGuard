import 'package:flutter_litert/flutter_litert.dart';
import '../models/imu_sample.dart';
import 'feature_extractor.dart';
import 'feature_stats.dart';

/// Loads the on-device TFLite swallow classifier and runs inference on
/// buffered IMU windows.
///
/// Model input: float32 tensor, shape [1, 48] — the 48 normalized
/// features (8 per axis × 6 IMU axes), in the exact order specified by
/// feature_stats.json.
/// Model output: float32 tensor, shape [1, 3] — softmax probabilities
/// for [normal, delayed_incomplete, aspiration_risk].
class SwallowClassifier {
  final FeatureStats stats;
  final FeatureExtractor _extractor;
  late final Interpreter _interpreter;
  bool _isLoaded = false;

  SwallowClassifier({required this.stats})
      : _extractor = FeatureExtractor(samplingRateHz: stats.samplingRateHz);

  bool get isLoaded => _isLoaded;

  static const String modelAssetPath =
      'assets/models/dysphagia_imu_model_float32.tflite';

  Future<void> loadModel() async {
    // Required on Flutter Web so flutter_litert loads its tflite-js/WASM
    // runtime before creating an Interpreter. It's a no-op on native
    // platforms (Android/iOS/desktop), so it's safe to always call.
    await initializeWeb();
    _interpreter = await Interpreter.fromAsset(modelAssetPath);
    _isLoaded = true;
  }

  /// Runs the full extract -> normalize -> infer pipeline on one buffered
  /// window of IMU samples. `window.length` should equal
  /// `stats.windowSamples` (300 by default), but this will still run on
  /// whatever is provided — callers are responsible for buffering the
  /// correct window size before calling this.
  ClassificationResult classify(List<ImuSample> window) {
    if (!_isLoaded) {
      throw StateError('SwallowClassifier.loadModel() must be awaited before classify()');
    }

    final rawFeatures = _extractor.extract(window);
    final normalized = stats.normalize(rawFeatures);

    final input = [normalized];
    final output = List.filled(1 * 3, 0.0).reshape([1, 3]);

    _interpreter.run(input, output);

    final probs = (output[0] as List).map((e) => (e as num).toDouble()).toList();
    var bestIdx = 0;
    var bestVal = probs[0];
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > bestVal) {
        bestVal = probs[i];
        bestIdx = i;
      }
    }

    return ClassificationResult(
      swallowClass: SwallowClass.fromIndex(bestIdx),
      probabilities: probs,
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    if (_isLoaded) {
      _interpreter.close();
    }
  }
}
