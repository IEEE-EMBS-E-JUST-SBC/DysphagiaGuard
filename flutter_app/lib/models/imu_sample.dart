/// A single raw IMU sample as pushed by the ESP32/MYOSA firmware to
/// /devices/<deviceId>/live in Firebase Realtime Database.
///
/// Expected shape written by firmware (one write per sample, ~100 Hz):
/// {
///   "ax": 0.01, "ay": -0.02, "az": 0.98,
///   "gx": 0.4,  "gy": -0.1,  "gz": 0.05,
///   "t":  1234567          // device millis() timestamp
/// }
class ImuSample {
  final double ax, ay, az;
  final double gx, gy, gz;
  final int deviceMillis;

  const ImuSample({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.deviceMillis,
  });

  factory ImuSample.fromMap(Map<dynamic, dynamic> map) {
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return ImuSample(
      ax: asDouble(map['ax']),
      ay: asDouble(map['ay']),
      az: asDouble(map['az']),
      gx: asDouble(map['gx']),
      gy: asDouble(map['gy']),
      gz: asDouble(map['gz']),
      deviceMillis: asInt(map['t']),
    );
  }

  /// Channel order MUST match feature_stats.json's "imu_channels".
  List<double> get channelsInOrder => [ax, ay, az, gx, gy, gz];
}

/// Result of running the TFLite model on one buffered window.
enum SwallowClass {
  normal,
  delayedIncomplete,
  aspirationRisk,
  unknown;

  static SwallowClass fromIndex(int i) {
    switch (i) {
      case 0:
        return SwallowClass.normal;
      case 1:
        return SwallowClass.delayedIncomplete;
      case 2:
        return SwallowClass.aspirationRisk;
      default:
        return SwallowClass.unknown;
    }
  }

  String get label {
    switch (this) {
      case SwallowClass.normal:
        return 'NORMAL SWALLOW';
      case SwallowClass.delayedIncomplete:
        return 'DELAYED / INCOMPLETE';
      case SwallowClass.aspirationRisk:
        return 'ASPIRATION RISK';
      case SwallowClass.unknown:
        return 'NO DATA';
    }
  }

  String get shortLabel {
    switch (this) {
      case SwallowClass.normal:
        return 'Normal';
      case SwallowClass.delayedIncomplete:
        return 'Delayed';
      case SwallowClass.aspirationRisk:
        return 'High risk';
      case SwallowClass.unknown:
        return '—';
    }
  }
}

class ClassificationResult {
  final SwallowClass swallowClass;
  final List<double> probabilities; // [normal, delayed, aspiration]
  final DateTime timestamp;

  const ClassificationResult({
    required this.swallowClass,
    required this.probabilities,
    required this.timestamp,
  });

  double get confidence {
    switch (swallowClass) {
      case SwallowClass.normal:
        return probabilities.isNotEmpty ? probabilities[0] : 0.0;
      case SwallowClass.delayedIncomplete:
        return probabilities.length > 1 ? probabilities[1] : 0.0;
      case SwallowClass.aspirationRisk:
        return probabilities.length > 2 ? probabilities[2] : 0.0;
      case SwallowClass.unknown:
        return 0.0;
    }
  }
}
