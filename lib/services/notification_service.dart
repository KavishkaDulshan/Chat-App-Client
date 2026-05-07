import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kIsWeb, defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';
import 'e2ee_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Flutter is initialized in the background isolate
  WidgetsFlutterBinding.ensureInitialized();

  if (message.data['type'] == 'chat_message') {
    final senderName = message.data['senderName'] ?? 'Someone';
    final msgType = message.data['msgType'] ?? 'text';
    final content = message.data['content'] ?? '';
    final senderId = message.data['senderId'] ?? '';
    final roomId = message.data['roomId'] ?? '';
    final previewEnabled = message.data['previewEnabled'] == 'true';
    
    String displayTitle = "New Message from $senderName";
    String displayBody = "Tap to view message";

    if (!previewEnabled) {
       // Just show generic notification
       if (msgType == 'image') {
         displayBody = "📷 Sent an image";
       } else if (msgType == 'audio') {
         displayBody = "🎵 Sent a voice message";
       }
    } else {
       // Preview IS enabled, try to show content
       displayTitle = senderName; // When showing content, title is just the sender's name
       if (msgType == 'image') {
         displayBody = "📷 Sent an image";
       } else if (msgType == 'audio') {
         displayBody = "🎵 Sent a voice message";
       } else if (content.isNotEmpty) {
          // Attempt decryption
          if (E2eeService().isE2EMessage(content)) {
              final authService = AuthService();
              final e2eService = E2eeService();
              
              try {
                const storage = FlutterSecureStorage();
                final userDataString = await storage.read(key: 'user_data');
                if (userDataString != null) {
                  final userMap = jsonDecode(userDataString);
                  final myUserId = userMap['_id'];
                  
                  final peerKey = await authService.getUserE2EEPublicKey(senderId);
                  if (peerKey != null && peerKey.isNotEmpty) {
                    final decrypted = await e2eService.decryptTextMessage(
                       encryptedPayload: content,
                       myUserId: myUserId,
                       peerUserId: senderId,
                       peerPublicKeyB64: peerKey,
                    );
                    if (decrypted != null) {
                      displayBody = decrypted;
                    } else {
                      displayBody = "🔒 Encrypted message";
                    }
                  } else {
                    displayBody = "🔒 Encrypted message";
                  }
                } else {
                  displayBody = "🔒 Encrypted message";
                }
              } catch(e) {
                print("Background Decryption Error: $e");
                displayBody = "🔒 Encrypted message";
              }
          } else {
              displayBody = content; // unencrypted text
          }
       }
    }

    await NotificationService().showLocalNotification(displayTitle, displayBody, payload: roomId);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initNotifications() async {
    if (_isInitialized) return;
    _isInitialized = true;

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

      // Initialize Local Notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
             print("🚀 Local Notification Tapped! Room: ${response.payload}");
             // You can use a global navigator key or Riverpod listener to navigate here
          }
        },
      );

      // Register Background Handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle Foreground Messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        // Since we are in the foreground, Riverpod handles UI updates.
        // If we want a heads-up notification while in app, we can uncomment below:
        // if (message.notification == null && message.data['type'] == 'chat_message') {
        //   _firebaseMessagingBackgroundHandler(message);
        // }
      });

    } catch (e) {
      print("❌ FCM Init Error: $e");
    }
  }

  Future<void> showLocalNotification(String title, String body, {String? payload}) async {
    if (!_isAndroid) return;
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'chat_messages', 
      'Chat Messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _localNotificationsPlugin.show(
      DateTime.now().millisecond, // random ID
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> setupInteractedMessage(dynamic context) async {
    if (!_isAndroid) return;

    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

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
