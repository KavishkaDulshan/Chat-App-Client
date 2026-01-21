import 'dart:io';
import 'package:flutter/material.dart'; // Required for BuildContext
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initNotifications() async {
    if (_isInitialized) return;

    // ------------------------------------------------
    // 1. SETUP LOCAL NOTIFICATIONS
    // ------------------------------------------------

    // Android Settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Linux Settings
    const LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    // === WINDOWS SETTINGS ===
    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'ViralChat',
          appUserModelId: 'com.viralchat.windows',
          guid: '8192667d-9226-4762-9f37-128a83424683',
        );

    // Combine them all
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    // Initialize the plugin
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap logic here if needed
        print("🔔 Notification Tapped: ${response.payload}");
      },
    );

    _isInitialized = true;
    print("✅ Local Notifications Initialized");

    // ------------------------------------------------
    // 2. WINDOWS GUARD (Skip FCM on Windows)
    // ------------------------------------------------
    if (!kIsWeb && Platform.isWindows) {
      print(
        "💻 Windows detected: FCM Disabled (Using Local Notifications only)",
      );
      return;
    }

    // ------------------------------------------------
    // 3. ANDROID/MOBILE LOGIC (Firebase FCM)
    // ------------------------------------------------
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print("🔥 FCM Permission Granted");
        // Optional: Get token here if needed for debugging
        // String? token = await messaging.getToken();
      }
    } catch (e) {
      print("❌ FCM Init Error: $e");
    }
  }

  // ------------------------------------------------
  // HELPER 1: Trigger Notification Manually (Fixes error G69E91ED9)
  // ------------------------------------------------
  Future<void> showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond, // Unique ID
      title,
      body,
      details,
    );
  }

  // ------------------------------------------------
  // HELPER 2: Handle Background Taps (Required by HomeScreen)
  // ------------------------------------------------
  Future<void> setupInteractedMessage(BuildContext context) async {
    if (kIsWeb || Platform.isWindows) return;

    // 1. App opened from Terminated State
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(context, initialMessage);
    }

    // 2. App opened from Background State
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessage(context, message);
    });
  }

  void _handleMessage(BuildContext context, RemoteMessage message) {
    if (message.data['type'] == 'chat_message') {
      print("🚀 Notification Tapped! Room: ${message.data['roomId']}");
      // Add navigation logic here if needed
    }
  }
}
