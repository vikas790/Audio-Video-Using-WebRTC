import 'package:flutter/material.dart';

import '../../../utils/constant.dart';

// App theme — white background across all screens
class AppTheme {
  AppTheme._();

  static const Color _background = Color(AppConstants.appBackgroundValue);
  static const Color _textPrimary = Color(0xFF2B2B2B);
  static const Color _textSecondary = Color(0xFF8A8A8A);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.light,
      surface: _background,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _background,
      canvasColor: _background,
      colorScheme: colorScheme.copyWith(
        surface: _background,
        onSurface: _textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: const IconThemeData(color: _textPrimary),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: _textPrimary),
        bodyMedium: TextStyle(color: _textPrimary),
        bodySmall: TextStyle(color: _textSecondary),
      ),
    );
  }
}
