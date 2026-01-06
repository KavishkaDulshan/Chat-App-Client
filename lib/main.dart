import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'providers/auth_provider.dart';

void main() {
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
    // Check if user is already logged in when app starts
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
      // LOGIC:
      // 1. If loading, show a spinner.
      // 2. If user exists, go to Home.
      // 3. Else, go to Login.
      home: authState.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (authState.user != null ? const HomeScreen() : const LoginScreen()),
    );
  }
}
