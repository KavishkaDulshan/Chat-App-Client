import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import 'contact_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoginMode = true;

  void _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty) return;

    // Remove keyboard focus so user sees the loading spinner
    FocusScope.of(context).unfocus();

    if (_isLoginMode) {
      await ref.read(authProvider.notifier).login(email, password);
    } else {
      final success = await ref
          .read(authProvider.notifier)
          .signUp(username, email, password);

      // Check 'mounted' to fix the "Do not use BuildContext across async gaps" warning
      if (!mounted) return;

      if (success) {
        setState(() => _isLoginMode = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account Created! Login now.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // FIX: Add '<AuthState>' to tell Dart this cannot be null
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }

      if (next.user != null) {
        final socketService = ref.read(socketServiceProvider);

        socketService.connect(next.user!, () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ContactScreen()),
          );
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(_isLoginMode ? "Login" : "Sign Up")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isLoginMode)
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username"),
              ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),

            authState.isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _handleAuth,
                    child: Text(_isLoginMode ? "Login" : "Sign Up"),
                  ),
            TextButton(
              onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
              child: Text(_isLoginMode ? "Create Account" : "Back to Login"),
            ),
          ],
        ),
      ),
    );
  }
}
