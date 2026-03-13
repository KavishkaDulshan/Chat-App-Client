import 'package:flutter/material.dart';

class AppTheme {
  // 1. Color Palette (Minimalistic & High Contrast)
  static const Color primary = Color(0xFF0F172A); // Deep Slate
  static const Color secondary = Color(0xFFF1F5F9); // Light Slate
  static const Color background = Color(0xFFF8FAFC); // Off-white Slate
  static const Color cardColor = Colors.white;
  static const Color myMessageColor = Color(0xFF0F172A);
  static const Color otherMessageColor = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  // 2. Text Styles
  static const TextStyle headerStyle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    letterSpacing: -0.8,
  );

  static const TextStyle nameStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle subTitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  // 3. Input Decoration (Minimalistic & Flat)
  static InputDecoration inputDecoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w400),
      prefixIcon: icon != null ? Icon(icon, color: textSecondary, size: 22) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}
