import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> initNotifications() async {
    // ------------------------------------------------
    // 1. SETUP LOCAL NOTIFICATIONS
    // ------------------------------------------------

    // Android Settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Linux Settings
    const LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    // === WINDOWS SETTINGS (FIXED) ===
    // Your version requires ALL THREE of these parameters:
    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'ViralChat',
          appUserModelId: 'com.viralchat.windows',
          guid:
              '8192667d-9226-4762-9f37-128a83424683', // Unique ID for your app
        );

    // Combine them all
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    // Initialize the plugin
    await _localNotifications.initialize(initSettings);

    // ------------------------------------------------
    // 2. WINDOWS GUARD
    // ------------------------------------------------
    if (!kIsWeb && Platform.isWindows) {
      print(
        "💻 Windows detected: Switching to Local Notifications (FCM Disabled)",
      );
      return;
    }

    // ------------------------------------------------
    // 3. ANDROID/WEB LOGIC (Firebase FCM)
    // ------------------------------------------------
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print("🔥 FCM Permission Granted");
        String? token = await messaging.getToken();
        print("🔥 FCM Token: $token");
      }
    } catch (e) {
      print("❌ FCM Init Error: $e");
    }
  }

  // ------------------------------------------------
  // HELPER: Trigger Notification Manually
  // ------------------------------------------------
  Future<void> showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'channel_id',
          'ViralChat Messages',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
  }
}
