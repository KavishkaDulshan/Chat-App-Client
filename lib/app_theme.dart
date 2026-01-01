import 'package:flutter/material.dart';

class AppTheme {
  // 1. Color Palette
  static const Color primary = Color(0xFF6B4EFF); // Modern Violet/Indigo
  static const Color secondary = Color(0xFFE0D9FF);
  static const Color background = Color(0xFFF5F7FB); // Soft Blue-Grey
  static const Color cardColor = Colors.white;
  static const Color myMessageColor = Color(0xFF6B4EFF);
  static const Color otherMessageColor = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF8A95A5);

  // 2. Text Styles
  static const TextStyle headerStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle nameStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle subTitleStyle = TextStyle(
    fontSize: 14,
    color: textSecondary,
    height: 1.4,
  );

  // 3. Input Decoration (Rounded & Clean)
  static InputDecoration inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textSecondary),
      prefixIcon: icon != null ? Icon(icon, color: textSecondary) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    );
  }
}
