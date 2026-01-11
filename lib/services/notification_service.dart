import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:developer';
import 'auth_service.dart'; // Import this

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final AuthService _authService = AuthService(); // Create instance

  Future<void> initNotifications() async {
    try {
      print("🔔 [DEBUG] Requesting Notification Permission...");

      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(alert: true, badge: true, sound: true);

      print("🔔 [DEBUG] Permission Status: ${settings.authorizationStatus}");

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print("🔔 [DEBUG] User granted permission. Fetching Token...");

        // This is the line that might hang if Play Services are missing
        final fcmToken = await _firebaseMessaging.getToken();

        if (fcmToken != null) {
          print("========================================");
          print("🔥 FCM TOKEN: $fcmToken");
          print("========================================");
          await _authService.sendFcmToken(fcmToken);
        } else {
          print("⚠️ [DEBUG] FCM Token is NULL");
        }
      } else {
        print("⚠️ [DEBUG] Permission DECLINED by user.");
      }

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      print("❌ [ERROR] Failed to init notifications: $e");
    }
  }
}

// Top-level function (must be outside any class)
// This runs when the app is completely closed and a notification arrives
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log("Handling a background message: ${message.messageId}");
}
