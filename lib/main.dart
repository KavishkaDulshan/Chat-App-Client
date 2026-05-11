import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'providers/auth_provider.dart';
import 'services/notification_service.dart';
import 'providers/socket_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/conversations_provider.dart';

void main() async {
  // Keep native splash until we're ready to show Flutter UI
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 1. Firebase must be first (required by FCM and Auth)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("⚠️ Firebase Init Warning: $e");
  }

  // 2. Remove native splash and render the app
  FlutterNativeSplash.remove();
  runApp(const ProviderScope(child: ChatApp()));

  // 3. Initialize notifications AFTER first frame (non-blocking)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService().initNotifications();
  });
}

class ChatApp extends ConsumerStatefulWidget {
  const ChatApp({super.key});

  @override
  ConsumerState<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends ConsumerState<ChatApp> with WidgetsBindingObserver {
  DateTime? _lastResumeTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(authProvider.notifier).checkAuthStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Debounce: only refresh if >5 seconds since last resume
      final now = DateTime.now();
      if (_lastResumeTime != null &&
          now.difference(_lastResumeTime!).inSeconds < 5) {
        return;
      }
      _lastResumeTime = now;

      final user = ref.read(authProvider).user;
      if (user != null) {
        // App resumed from background on mobile.
        // The socket might have disconnected or missed events.
        try {
          final socket = ref.read(socketServiceProvider).socket;
          if (!socket.connected) {
            socket.connect();
          }
        } catch (_) {}
        
        // Fetch any data missed while backgrounded
        ref.read(contactProvider.notifier).loadPendingRequests();
        ref.read(conversationsProvider.notifier).loadChats(forceRefresh: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ViralChat',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(),
      ),
      home: authState.isInitializing
          ? const _SplashLoadingScreen()
          : authState.user != null
              ? const HomeScreen()
              : const LoginScreen(),
    );
  }
}

/// Shown for the ~50ms between Flutter first frame and checkAuthStatus completion.
/// Matches the native splash color so the transition is seamless.
class _SplashLoadingScreen extends StatelessWidget {
  const _SplashLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
  }
}
