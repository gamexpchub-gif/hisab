import 'package:flutter/material.dart';

/// Design tokens — white background, premium purple/blue, soft shadows.
class C {
  static const bg = Color(0xFFF7F8FC);
  static const surface = Colors.white;
  static const ink = Color(0xFF12163A);
  static const ink2 = Color(0xFF3B4064);
  static const muted = Color(0xFF6B7094);
  static const line = Color(0xFFE7E9F4);
  static const navy = Color(0xFF13185A);
  static const blue = Color(0xFF3155C8);
  static const blue2 = Color(0xFF2F6BFF);
  static const purple = Color(0xFF7044D8);
  static const purple2 = Color(0xFF5B2EE0);
  static const green = Color(0xFF16A36A);
  static const red = Color(0xFFDC4545);
  static const orange = Color(0xFFF08A24);
  static const field = Color(0xFFF4F5FB);

  static const primaryGradient = LinearGradient(colors: [Color(0xFF5B2EE0), Color(0xFF3A2BC9)]);
  static const brandGradient = LinearGradient(colors: [Color(0xFF7044D8), Color(0xFFA23BE0)]);

  static const shadow = [
    BoxShadow(color: Color(0x24282E78), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -10),
    BoxShadow(color: Color(0x0D282E78), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static const fabShadow = [
    BoxShadow(color: Color(0x8C4624D2), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -8),
  ];
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.purple2, surface: C.bg),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: C.ink,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFBFBFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF9C85F0), width: 1.6)),
      labelStyle: const TextStyle(color: C.ink2),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
