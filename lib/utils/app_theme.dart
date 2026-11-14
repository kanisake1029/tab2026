import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get modernLight {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9), // Light Slate
      primaryColor: const Color(0xFF3B82F6),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF3B82F6),
        secondary: Color(0xFF06B6D4),
        surface: Colors.white,
      ),
      fontFamily: 'BIZUDPGothic',
      fontFamilyFallback: const ['Meiryo', 'Yu Gothic', 'Hiragino Sans'], 
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'BIZUDPGothic',
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF3B82F6),
        unselectedItemColor: Color(0xFF94A3B8),
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
    );
  }

  /// スマホ向けに詰めたテーマ（ボタン・一覧・タブ・上部バーを低く）
  static ThemeData compact(ThemeData base) => base.copyWith(
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        appBarTheme: base.appBarTheme.copyWith(
          toolbarHeight: 44,
          titleTextStyle: const TextStyle(fontFamily: 'BIZUDPGothic', color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        listTileTheme: const ListTileThemeData(dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12), minVerticalPadding: 4),
        tabBarTheme: const TabBarThemeData(labelPadding: EdgeInsets.symmetric(horizontal: 10)),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 34))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: const Size(0, 32))),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: const Size(0, 30))),
        dialogTheme: const DialogThemeData(insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 20)),
      );

  // Trajectory Colors (Match Grades 4=A, 3=B, 2=C, 1=D)
  static Color getTrajectoryColor(int trajectory) {
    switch (trajectory) {
      case 4: return getGradeColor('A');
      case 3: return getGradeColor('B');
      case 2: return getGradeColor('C');
      case 1: return getGradeColor('D');
      default: return Colors.grey;
    }
  }

  // Grade Text Colors
  static Color getGradeColor(String grade) {
    if (grade.startsWith('S')) return const Color(0xFFF8BBD0); // Light Pink
    if (grade.startsWith('A')) return const Color(0xFFE91E63); // Pink
    if (grade.startsWith('B')) return const Color(0xFFF44336); // Red
    if (grade.startsWith('C')) return const Color(0xFFFF9800); // Orange
    if (grade.startsWith('D')) return const Color(0xFFA1887F); // Brown
    if (grade.startsWith('E')) return const Color(0xFF8BC34A); // Light Green
    if (grade.startsWith('F')) return const Color(0xFF29B6F6); // Light Blue
    return const Color(0xFF9E9E9E); // Grey
  }
}
