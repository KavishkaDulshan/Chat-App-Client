import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'providers/auth_provider.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase (Safe for all platforms including Windows)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("✅ Firebase Initialized");
  } catch (e) {
    print("⚠️ Firebase Init Warning: $e");
  }

  // 2. Initialize Notifications (Will skip FCM on Windows automatically)
  await NotificationService().initNotifications();

  runApp(const ProviderScope(child: ChatApp()));
}

class ChatApp extends ConsumerStatefulWidget {
  const ChatApp({super.key});

  @override
  ConsumerState<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends ConsumerState<ChatApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authProvider.notifier).checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ViralChat',
      home: authState.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (authState.user != null ? const HomeScreen() : const LoginScreen()),
    );
  }
}
