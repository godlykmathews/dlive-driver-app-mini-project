import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const _baseUrl = 'https://driver-backend-5sb9.onrender.com/api/v1';
const _intervalSeconds = 45;

/// Call once at app startup before runApp
Future<void> initLocationService() async {
  // On Android 8+, the notification channel must exist before the
  // foreground service posts its notification, otherwise Android 13+
  // throws CannotPostForegroundServiceNotificationException and crashes.
  if (Platform.isAndroid) {
    const channel = AndroidNotificationChannel(
      'dlive_location',
      'Dlive Driver Location',
      description: 'Shows while location tracking is active',
      importance: Importance.low,
    );
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'dlive_location',
      initialNotificationTitle: 'Dlive Driver',
      initialNotificationContent: 'Location tracking active',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onServiceStart,
      onBackground: _onIosBackground,
    ),
  );
}

/// Start tracking — request permission then start service.
/// Never throws; failures are silently swallowed so callers don't crash.
Future<void> startLocationTracking() async {
  try {
    final ok = await _ensurePermission();
    if (!ok) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) await service.startService();
  } catch (_) {
    // Don't propagate — location tracking is best-effort
  }
}

/// Stop tracking — send stop signal to background isolate
Future<void> stopLocationTracking() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
}

Future<bool> _ensurePermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  LocationPermission perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  return perm == LocationPermission.always ||
      perm == LocationPermission.whileInUse;
}

// ── Background isolate ────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stop').listen((_) => service.stopSelf());

  // Send immediately, then on interval
  await _sendLocation();
  Timer.periodic(const Duration(seconds: _intervalSeconds), (_) {
    _sendLocation();
  });
}

Future<void> _sendLocation() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) return;

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.medium,
        intervalDuration: const Duration(seconds: _intervalSeconds),
        timeLimit: const Duration(seconds: 20),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.medium,
      );
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );

    await http
        .post(
          Uri.parse('$_baseUrl/location'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy': pos.accuracy,
          }),
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // Silently retry on next interval
  }
}
