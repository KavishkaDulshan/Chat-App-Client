import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      if (next.errorMessage != null && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: TweenAnimationBuilder(
              duration: const Duration(milliseconds: 600),
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, double value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 1. Logo
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 64,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isLoginMode ? 'Welcome Back' : 'Create Account',
                    style: AppTheme.headerStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoginMode
                        ? 'Sign in to continue chatting'
                        : 'Sign up to get started',
                    style: AppTheme.subTitleStyle,
                  ),
                  const SizedBox(height: 48),

                  // 2. Form Fields
                  if (!_isLoginMode)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: TextField(
                        controller: _usernameController,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: AppTheme.inputDecoration(
                          'Username',
                          icon: Icons.person_outline,
                        ),
                      ),
                    ),
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: AppTheme.inputDecoration(
                      'Email Address',
                      icon: Icons.email_outlined,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: AppTheme.inputDecoration(
                      'Password',
                      icon: Icons.lock_outline,
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 32),

                  // 3. Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: authState.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _handleAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _isLoginMode ? "Log In" : "Sign Up",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                  ),

                  // 4. Toggle Button
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () {
                      setState(() => _isLoginMode = !_isLoginMode);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: _isLoginMode
                            ? "Don't have an account? "
                            : "Already have an account? ",
                        style: const TextStyle(color: AppTheme.textSecondary),
                        children: [
                          TextSpan(
                            text: _isLoginMode ? "Sign Up" : "Log In",
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
      ),
    );
  }
}
