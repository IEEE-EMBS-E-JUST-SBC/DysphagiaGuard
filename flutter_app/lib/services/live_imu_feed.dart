import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/imu_sample.dart';
import '../inference/swallow_classifier.dart';
import '../inference/heuristic_swallow_classifier.dart';

/// Subscribes to /devices/<deviceId>/live, where the ESP32/MYOSA firmware
/// writes one raw IMU sample per update (~100 Hz, matching
/// feature_stats.json's sampling_rate_hz). Buffers samples into
/// non-overlapping windows of `windowSamples` length.
///
/// Firebase write shape expected from firmware, one write per sample:
///   /devices/<deviceId>/live = {
///     "ax": .., "ay": .., "az": ..,
///     "gx": .., "gy": .., "gz": ..,
///     "t": <device millis>
///   }
///
/// Classification pipeline: on start(), the feed first runs a 30-second
/// gyro/accelerometer calibration pass (device must be held still) to
/// capture per-axis zero-offset and resting noise floor. Once calibrated,
/// each buffered window is classified using [HeuristicSwallowClassifier]
/// (a rule-based classifier over the calibrated gyro/az motion pattern —
/// see that file for the reasoning). The on-device TinyML model
/// ([SwallowClassifier]) is still loaded and kept wired up for its
/// intended future role, but its output is not used to make the call
/// right now.
class LiveImuFeed {
  final String deviceId;
  final SwallowClassifier classifier;
  final int windowSamples;
  final double samplingRateHz;
  final Duration calibrationDuration;

  final DatabaseReference _liveRef;
  StreamSubscription<DatabaseEvent>? _sub;

  final List<ImuSample> _buffer = [];
  int? _lastSeenMillis;

  final CalibrationCollector _calibrationCollector;
  GyroCalibration? _calibration;
  HeuristicSwallowClassifier? _heuristicClassifier;

  final _connectionController = StreamController<bool>.broadcast();
  final _sampleController = StreamController<ImuSample>.broadcast();
  final _resultController = StreamController<ClassificationResult>.broadcast();
  final _calibrationProgressController = StreamController<double>.broadcast();
  final _calibrationDoneController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<ImuSample> get sampleStream => _sampleController.stream;
  Stream<ClassificationResult> get resultStream => _resultController.stream;

  /// 0.0 -> 1.0 progress of the 30s calibration hold. Only meaningful
  /// while [isCalibrating] is true.
  Stream<double> get calibrationProgressStream => _calibrationProgressController.stream;

  /// Fires once with `true` when calibration finishes successfully, or
  /// `false` if it failed (e.g. feed dropped before enough samples).
  Stream<bool> get calibrationDoneStream => _calibrationDoneController.stream;

  bool get isCalibrating => _calibration == null;
  GyroCalibration? get calibration => _calibration;

  /// 0.0 -> 1.0 fill level of the current buffering window, for UI feedback.
  double get bufferProgress => (_buffer.length / windowSamples).clamp(0.0, 1.0);

  LiveImuFeed({
    required this.deviceId,
    required this.classifier,
    required this.windowSamples,
    this.samplingRateHz = 100.0,
    this.calibrationDuration = const Duration(seconds: 30),
  })  : _liveRef = FirebaseDatabase.instance.ref('devices/$deviceId/live'),
        _calibrationCollector = CalibrationCollector(duration: calibrationDuration);

  /// Last error message from the Firebase listener, if any. Null means no
  /// error has occurred (though it may also mean no data has arrived yet —
  /// check `_connectionController`/UI "connected" state separately).
  String? lastError;

  Timer? _calibrationTicker;

  void start() {
    _calibrationCollector.start();
    _calibrationTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_calibration == null) {
        _calibrationProgressController.add(_calibrationCollector.progress);
      }
    });

    _sub = _liveRef.onValue.listen(
          (event) {
        final data = event.snapshot.value;
        if (data == null) {
          // Path exists but has no data yet, or was just cleared. Not an
          // error, but also not a connected sample — don't mark connected.
          return;
        }
        if (data is Map) {
          final sample = ImuSample.fromMap(Map<dynamic, dynamic>.from(data));

          // Skip duplicate/stale writes (same device timestamp as last seen).
          if (_lastSeenMillis != null && sample.deviceMillis == _lastSeenMillis) {
            return;
          }
          _lastSeenMillis = sample.deviceMillis;

          lastError = null;
          _connectionController.add(true);
          _sampleController.add(sample);

          if (_calibration == null) {
            _calibrationCollector.addSample(sample);
            if (_calibrationCollector.isComplete) {
              _finishCalibration();
            }
            return; // Don't buffer for classification until calibrated.
          }

          _buffer.add(sample);

          if (_buffer.length >= windowSamples) {
            final window = List<ImuSample>.from(_buffer.take(windowSamples));
            _buffer.clear();

            final heuristic = _heuristicClassifier;
            if (heuristic == null) return;

            try {
              final result = heuristic.classify(window);
              _resultController.add(result);
            } catch (e) {
              // Malformed window — drop it, next one will retry.
              // ignore: avoid_print
              print('LiveImuFeed: classification failed for window: $e');
            }
          }
        } else {
          // ignore: avoid_print
          print('LiveImuFeed: unexpected data shape at $deviceId/live: '
              '${data.runtimeType} -> $data');
        }
      },
      onError: (Object error, StackTrace stack) {
        lastError = error.toString();
        // ignore: avoid_print
        print('LiveImuFeed: Firebase listener error on $deviceId/live: $error');
        _connectionController.add(false);
      },
    );
  }

  void _finishCalibration() {
    _calibrationTicker?.cancel();
    final cal = _calibrationCollector.finalize();
    if (cal == null) {
      lastError = 'Calibration failed: not enough steady samples captured. '
          'Keep the device still and check the connection.';
      _calibrationDoneController.add(false);
      // Restart calibration automatically so the UI isn't stuck.
      _calibrationCollector.start();
      return;
    }
    _calibration = cal;
    _heuristicClassifier = HeuristicSwallowClassifier(
      calibration: cal,
      samplingRateHz: samplingRateHz,
    );
    _calibrationProgressController.add(1.0);
    _calibrationDoneController.add(true);
  }

  void stop() {
    _sub?.cancel();
    _calibrationTicker?.cancel();
  }

  void dispose() {
    stop();
    _connectionController.close();
    _sampleController.close();
    _resultController.close();
    _calibrationProgressController.close();
    _calibrationDoneController.close();
  }
}
