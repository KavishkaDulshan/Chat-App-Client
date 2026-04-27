import 'package:flutter/foundation.dart'; // For kIsWeb, defaultTargetPlatform
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  /// Returns true only on Android (the only platform with push notifications)
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initNotifications() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Only initialize FCM on Android
    if (!_isAndroid) {
      print("💻 Non-Android platform: Notifications disabled");
      return;
    }

    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print("🔥 FCM Permission Granted");
      }
    } catch (e) {
      print("❌ FCM Init Error: $e");
    }
  }

  /// Show local notification — only works on Android
  Future<void> showLocalNotification(String title, String body) async {
    // No-op on non-Android platforms
  }

  /// Handle background notification taps — only works on Android
  Future<void> setupInteractedMessage(dynamic context) async {
    if (!_isAndroid) return;

    try {
      // 1. App opened from Terminated State
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

      // 2. App opened from Background State
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleMessage(message);
      });
    } catch (e) {
      print("❌ FCM Interacted Message Error: $e");
    }
  }

  void _handleMessage(RemoteMessage message) {
    if (message.data['type'] == 'chat_message') {
      print("🚀 Notification Tapped! Room: ${message.data['roomId']}");
    }
  }
}
