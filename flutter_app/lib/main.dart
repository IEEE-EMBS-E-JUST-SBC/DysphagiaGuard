import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

// DysphagiaGuard companion app.
//
// Subscribes to Firebase Realtime Database at:
//   /devices/<deviceId>/live
// which the ESP32/MYOSA firmware writes raw 6-axis IMU samples to over
// WiFi (~100 Hz). This app buffers each 3-second window of samples,
// extracts the same 48 features used during training, and runs the
// on-device TinyML classifier (TFLite) to detect normal / delayed /
// aspiration-risk swallow events in real time — entirely on-device,
// no cloud inference required.
//
// Before running:
//   1. flutterfire configure   (generates a real firebase_options.dart
//      for YOUR Firebase project, replacing the placeholder one here)
//   2. Make sure `deviceId` below matches the DEVICE_ID the firmware
//      writes under in Firebase.
//   3. Ensure assets/models/dysphagia_imu_model_float32.tflite and
//      assets/models/feature_stats.json are present (see pubspec.yaml).

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const DysphagiaGuardApp());
}

class DysphagiaGuardApp extends StatelessWidget {
  const DysphagiaGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DysphagiaGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.violet,
          brightness: Brightness.dark,
          surface: AppColors.surface,
          secondary: AppColors.cyan,
          tertiary: AppColors.pink,
        ),
        fontFamily: 'Roboto',
      ),
      home: const DashboardScreen(deviceId: 'dysphagiaguard-01'),
    );
  }
}
