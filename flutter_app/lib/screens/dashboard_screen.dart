import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../inference/feature_stats.dart';
import '../inference/swallow_classifier.dart';
import '../models/imu_sample.dart';
import '../services/live_imu_feed.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_banner.dart';
import '../widgets/live_waveform.dart';
import '../widgets/metric_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final String deviceId;
  const DashboardScreen({super.key, required this.deviceId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _waveformMaxSamples = 150;
  static const _historyMaxItems = 30;

  SwallowClassifier? _classifier;
  LiveImuFeed? _feed;

  bool _modelLoading = true;
  String? _modelError;
  bool _connected = false;

  ClassificationResult? _latestResult;
  double _bufferProgress = 0.0;

  bool _calibrating = true;
  double _calibrationProgress = 0.0;
  String? _calibrationError;

  final Queue<double> _waveformSamples = Queue<double>();
  final List<ClassificationResult> _history = [];

  StreamSubscription? _connSub;
  StreamSubscription? _sampleSub;
  StreamSubscription? _resultSub;
  StreamSubscription? _calibProgressSub;
  StreamSubscription? _calibDoneSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final stats = await FeatureStats.loadFromAsset('assets/models/feature_stats.json');
      final classifier = SwallowClassifier(stats: stats);
      await classifier.loadModel();

      final feed = LiveImuFeed(
        deviceId: widget.deviceId,
        classifier: classifier,
        windowSamples: stats.windowSamples,
      );

      _connSub = feed.connectionStream.listen((c) {
        if (mounted) setState(() => _connected = c);
      });
      _sampleSub = feed.sampleStream.listen((sample) {
        if (!mounted) return;
        setState(() {
          _waveformSamples.add(sample.az);
          while (_waveformSamples.length > _waveformMaxSamples) {
            _waveformSamples.removeFirst();
          }
          _bufferProgress = feed.bufferProgress;
        });
      });
      _resultSub = feed.resultStream.listen((result) {
        if (!mounted) return;
        setState(() {
          _latestResult = result;
          _history.insert(0, result);
          if (_history.length > _historyMaxItems) {
            _history.removeLast();
          }
        });
      });
      _calibProgressSub = feed.calibrationProgressStream.listen((p) {
        if (!mounted) return;
        setState(() => _calibrationProgress = p);
      });
      _calibDoneSub = feed.calibrationDoneStream.listen((success) {
        if (!mounted) return;
        setState(() {
          // On failure the feed restarts calibration itself, so this stays
          // true; on success it flips to false and the live view takes over.
          _calibrating = feed.isCalibrating;
          _calibrationError = success
              ? null
              : 'Calibration needs a steadier hold — restarting automatically.';
        });
      });

      feed.start();

      setState(() {
        _classifier = classifier;
        _feed = feed;
        _modelLoading = false;
      });
    } catch (e) {
      setState(() {
        _modelError = e.toString();
        _modelLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _sampleSub?.cancel();
    _resultSub?.cancel();
    _calibProgressSub?.cancel();
    _calibDoneSub?.cancel();
    _feed?.dispose();
    _classifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.9, -1.0),
            radius: 1.6,
            colors: [Color(0xFF1B1440), AppColors.background],
            stops: [0.0, 0.6],
          ),
        ),
        child: _modelLoading
            ? const _LoadingView()
            : _modelError != null
            ? _ErrorView(message: _modelError!)
            : _buildDashboard(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: _connected ? AppColors.mint : Colors.white70,
                  shape: BoxShape.circle,
                  boxShadow: _connected
                      ? [BoxShadow(color: AppColors.mint.withOpacity(0.8), blurRadius: 10)]
                      : null,
                ),
              ),
              Text(
                'DysphagiaGuard',
                style: AppText.statusWord.copyWith(fontSize: 20, color: Colors.white),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.deviceId,
                    style: AppText.caption.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final result = _calibrating ? null : _latestResult;
    final swallowClass = result?.swallowClass ?? SwallowClass.unknown;
    final probs = result?.probabilities ?? const [0.0, 0.0, 0.0];
    final waveColor = AppColors.forSwallowClass(swallowClass);

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppColors.violet,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!_connected) _NoSignalBanner(),
          if (!_connected) const SizedBox(height: 16),

          if (_calibrating && _connected) ...[
            _CalibrationBanner(
              progress: _calibrationProgress,
              error: _calibrationError,
            ),
            const SizedBox(height: 16),
          ],

          AlertBanner(
            swallowClass: swallowClass,
            probabilities: probs,
            bufferProgress: _calibrating ? 0.0 : _bufferProgress,
            connected: _connected && !_calibrating,
          ),

          const SizedBox(height: 20),

          // Signature live waveform — the IMU signal, alive on screen.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: AppColors.glassCard(AppColors.cyan, borderOpacity: 0.28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, size: 15, color: AppColors.cyan),
                        const SizedBox(width: 6),
                        Text('LARYNGEAL SIGNAL (az)', style: AppText.metricLabel),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${(_bufferProgress * 100).toStringAsFixed(0)}% buffered',
                        style: AppText.caption.copyWith(color: AppColors.cyan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LiveWaveform(samples: _waveformSamples, color: waveColor),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'CLASSIFICATION',
                  value: swallowClass.shortLabel,
                  subtitle: _calibrating
                      ? 'calibrating…'
                      : result == null
                          ? 'waiting for data'
                          : 'confidence ${(result.confidence * 100).toStringAsFixed(0)}%',
                  icon: Icons.psychology_alt_rounded,
                  accent: waveColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricCard(
                  title: 'EVENTS LOGGED',
                  value: '${_history.length}',
                  subtitle: 'this session',
                  icon: Icons.history_rounded,
                  accent: AppColors.pink,
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              Text('EVENT HISTORY', style: AppText.metricLabel),
            ],
          ),
          const SizedBox(height: 12),

          if (_history.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: AppColors.glassCard(AppColors.slate, borderOpacity: 0.22),
              child: Text(
                'No swallow events classified yet.\nWaiting for the first buffered window.',
                textAlign: TextAlign.center,
                style: AppText.body,
              ),
            )
          else
            ..._history.map((r) => EventHistoryTile(result: r)),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_rounded, size: 16, color: AppColors.violet),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'On-device TinyML inference runs directly on this device using raw '
                        'IMU samples relayed by the wearable through Firebase. Each '
                        'session starts with a brief calibration to learn your baseline '
                        'sensor readings before classifying swallow events. No sensor '
                        'data leaves this device for classification.',
                    style: AppText.caption.copyWith(height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppColors.brandGradient.createShader(bounds),
            child: const Icon(Icons.favorite_rounded, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: AppColors.violet, strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          const Text('Loading TinyML model…', style: AppText.body),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppColors.glassCard(AppColors.coral),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.coral, size: 40),
              const SizedBox(height: 16),
              Text(
                'Could not load the classifier model.',
                style: AppText.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, style: AppText.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalibrationBanner extends StatelessWidget {
  final double progress; // 0.0 -> 1.0
  final String? error;

  const _CalibrationBanner({required this.progress, this.error});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.glassCard(AppColors.violet, borderOpacity: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: AppColors.violet, strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Calibrating — hold still',
                  style: AppText.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                ),
              ),
              Text('$pct%', style: AppText.metricLabel.copyWith(color: AppColors.violet)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.hairline,
              valueColor: const AlwaysStoppedAnimation(AppColors.violet),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Keep the wearable still for about 30 seconds so the app can learn '
            'your resting sensor baseline before classifying swallow events.',
            style: AppText.caption,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: AppText.caption.copyWith(color: AppColors.amber)),
          ],
        ],
      ),
    );
  }
}

class _NoSignalBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppColors.glassCard(AppColors.gold, borderOpacity: 0.4),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No data from the wearable yet. Check that the device is powered and connected to WiFi.',
              style: AppText.body.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}