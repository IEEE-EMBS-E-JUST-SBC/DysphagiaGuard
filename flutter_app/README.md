# DysphagiaGuard — Flutter Companion App

On-device swallow & aspiration-risk monitor. Reads raw 6-axis IMU samples
pushed to Firebase by the ESP32/MYOSA wearable, buffers 3-second windows,
extracts features, and runs a TinyML (TFLite) classifier **directly on
the phone** — no cloud inference.

## What changed from the template

This was adapted from a physiological/environmental monitoring template
(reading a `score`/`rp`/`re` composite). Everything has been re-pointed at
DysphagiaGuard's actual pipeline:   

| Area | Was | Now |
|---|---|---|
| Firebase path | `/devices/<id>/live` → `{score, level, rp, re, tempC, updatedAtMs}` | `/devices/<id>/live` → `{ax, ay, az, gx, gy, gz, t}` (raw IMU, one write per sample) |
| Classification | Threshold on composite score | TFLite model output (normal / delayed-incomplete / aspiration-risk) |
| Firebase project | Real project `bioflex-237aa` (had live API keys) | Placeholder `dysphagiaguard` project — **you must run `flutterfire configure`** |
| UI | Score gauge + Rp/Re cards | Live IMU waveform, buffer-fill ring, 3-class probability bars, event history log |

**Security note:** the original `firebase_options.dart` you uploaded contained
real, live API keys for an existing Firebase project. Those have been
stripped and replaced with placeholders — do not reuse a stranger's
production keys in a renamed app. Run `flutterfire configure` against
your own project.

## Setup

```bash
flutter pub get

# Generates real Firebase credentials for YOUR project,
# overwrites lib/firebase_options.dart
flutterfire configure

# Point the app at your device's Firebase key — edit lib/main.dart:
#   home: const DashboardScreen(deviceId: 'your-device-id')

flutter run
```

The app expects these two files (already included) as bundled assets:
- `assets/models/dysphagia_imu_model_float32.tflite`
- `assets/models/feature_stats.json`

These come straight from the Colab training notebook's export step. If
you retrain the model, re-copy both files here — they must match
exactly (feature order + normalization stats are baked into
`feature_stats.json`, and the app trusts it completely).

## Firmware contract

The ESP32/MYOSA firmware should write to `/devices/<deviceId>/live` once
per IMU sample (~100 Hz to match `feature_stats.json`'s
`sampling_rate_hz`):

```json
{
  "ax": 0.01, "ay": -0.02, "az": 0.98,
  "gx": 0.4,  "gy": -0.1,  "gz": 0.05,
  "t": 1234567
}
```

`t` is the device's `millis()` — used only to detect duplicate/stale
writes, not for wall-clock display. The app buffers 300 consecutive
samples (3 seconds at 100 Hz) into one window, runs one classification
per window, then starts a fresh buffer — non-overlapping windows, matching
how the training data was constructed.

`database.rules.json` has been updated to validate this new shape
(`ax, ay, az, gx, gy, gz, t` instead of `score, level, rp, re, tempC,
updatedAtMs`). Deploy it with:

```bash
firebase deploy --only database
```

## On-device inference pipeline (how it actually works)

1. `LiveImuFeed` listens to the Firebase path and buffers incoming samples.
2. Every 300 samples, `FeatureExtractor` computes 8 features per axis
   (mean, std, RMS, peak, energy, zero-crossing rate, spectral centroid,
   spectral flatness) — 48 features total, in the exact order the model
   was trained on.
3. `SimpleFFT` computes spectral centroid/flatness using a **direct DFT**
   (not a padded FFT) — this was deliberately chosen because the training
   pipeline (numpy `rfft`) operates on the raw 300-sample window without
   zero-padding. An earlier padded-FFT approach was verified against
   numpy and, while mathematically correct as an FFT, produced ~10%
   drift in spectral features vs. training due to the padding changing
   bin spacing. The direct DFT matches numpy to floating-point precision.
   At 300 samples computed once per 3-second window, the O(N²) cost is
   trivial on a phone.
4. `FeatureStats.normalize()` applies the same `(x - mean) / scale` used
   by scikit-learn's `StandardScaler` during training.
5. `SwallowClassifier` runs the TFLite interpreter and returns softmax
   probabilities for the 3 classes.

## Known limitations / next steps

- **Model is trained on synthetic data.** See the Colab notebook — retrain
  on real labeled recordings before relying on this for actual patient
  monitoring. The pipeline (feature extraction, normalization, model
  architecture) stays the same; only the training data needs to change.
- **Non-overlapping windows** means there's up to a 3-second delay between
  a swallow event and its classification appearing. If you need faster
  response, consider overlapping windows (e.g. classify every 1s using
  the trailing 3s of samples) — this requires re-wiring `LiveImuFeed`'s
  buffering logic to a sliding window instead of take-and-clear.
- **No authentication** — `database.rules.json` still allows open
  read/write. Fine for a prototype, not for a shipped product handling
  health data.
