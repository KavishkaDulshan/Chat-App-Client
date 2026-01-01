import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import 'home_screen.dart';
import '../app_theme.dart'; // Import Theme

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
    FocusScope.of(context).unfocus();

    if (_isLoginMode) {
      await ref.read(authProvider.notifier).login(email, password);
    } else {
      final success = await ref
          .read(authProvider.notifier)
          .signUp(username, email, password);

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

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (next.user != null) {
        final socketService = ref.read(socketServiceProvider);
        socketService.connect(next.user!, () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        });
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background, // Nice background color
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
            ), // Limit width on Desktop
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Logo / Header
                const Icon(
                  Icons.chat_bubble_rounded,
                  size: 64,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _isLoginMode ? "Welcome Back" : "Create Account",
                  textAlign: TextAlign.center,
                  style: AppTheme.headerStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLoginMode
                      ? "Sign in to continue chatting"
                      : "Join the conversation today",
                  textAlign: TextAlign.center,
                  style: AppTheme.subTitleStyle,
                ),
                const SizedBox(height: 32),

                // 2. The Form Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (!_isLoginMode) ...[
                        TextField(
                          controller: _usernameController,
                          decoration: AppTheme.inputDecoration(
                            "Username",
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: AppTheme.inputDecoration(
                          "Email",
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: AppTheme.inputDecoration(
                          "Password",
                          icon: Icons.lock_outline,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: authState.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _handleAuth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  _isLoginMode ? "Login" : "Sign Up",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                // 4. Toggle Button
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: RichText(
                    text: TextSpan(
                      text: _isLoginMode
                          ? "Don't have an account? "
                          : "Already have an account? ",
                      style: const TextStyle(color: AppTheme.textSecondary),
                      children: [
                        TextSpan(
                          text: _isLoginMode ? "Sign Up" : "Login",
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
