import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import 'home_screen.dart';
import '../app_theme.dart';
import 'otp_verification_screen.dart'; // <--- IMPORTANT IMPORT

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

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (_isLoginMode) {
      // --- LOGIN LOGIC ---
      await ref.read(authProvider.notifier).login(email, password);
    } else {
      // --- SIGN UP LOGIC ---
      final success = await ref
          .read(authProvider.notifier)
          .signUp(username, email, password);

      if (!mounted) return;

      if (success) {
        // --- THE FIX IS HERE ---
        // 1. We DO NOT set _isLoginMode = true.
        // 2. We navigate to the Verification Screen.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(email: email),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code sent! Please check your email.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign up failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Listen for Auth Success (Only for Login, not Sign Up)
    ref.listen(authProvider, (previous, next) {
      if (next.user != null && _isLoginMode) {
        // Only navigate if we are in Login Mode.
        // Sign Up success is handled manually in _handleAuth to go to OTP screen.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      if (next.errorMessage != null && !next.isLoading) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. Logo or Header
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 80,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  _isLoginMode ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),

                // 2. Form Fields
                if (!_isLoginMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),

                // 3. Action Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: authState.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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

                // 4. Toggle Button
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    // This allows the USER to switch modes manually
                    setState(() => _isLoginMode = !_isLoginMode);
                  },
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
