import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF181818);
  static const green = Color(0xFF1DB954);
  static const secondary = Color(0xFFB3B3B3);
  static const purple = Color(0xFF913BEB);
  static const pink = Color(0xFFEE278C);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: green,
      secondary: purple,
      surface: surface,
      onPrimary: Colors.black,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: green,
      thumbColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      trackHeight: 3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF24242D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
    ),
  );
  static ThemeData accent(int color) {
    final primary = Color(color);
    return dark.copyWith(
      colorScheme: dark.colorScheme.copyWith(primary: primary),
      sliderTheme: dark.sliderTheme.copyWith(activeTrackColor: primary),
    );
  }
}
