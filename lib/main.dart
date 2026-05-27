import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/presentation/home_screen.dart';

export 'features/home/presentation/home_screen.dart';
export 'features/profile/presentation/profile_settings_screen.dart';
export 'features/workout/presentation/add_workout_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '근육 성장 일기',
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Noto Sans KR',
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF3182F6),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFE8F2FF),
          onPrimaryContainer: Color(0xFF111827),
          secondary: Color(0xFF06B6D4),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFE0F7FD),
          onSecondaryContainer: Color(0xFF164E63),
          tertiary: Color(0xFF8B5CF6),
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFFF1EBFF),
          onTertiaryContainer: Color(0xFF4C1D95),
          error: Color(0xFFEF4444),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF111827),
          onSurfaceVariant: Color(0xFF6B7280),
          outline: Color(0xFFE1E8F2),
          outlineVariant: Color(0xFFE8EEF6),
          surfaceContainerHighest: Color(0xFFF8FBFF),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF6F8FB),
          foregroundColor: Color(0xFF111827),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE8EEF6)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3182F6),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3182F6),
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: Color(0xFFE1E8F2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.white,
            selectedBackgroundColor: const Color(0xFFE8F2FF),
            selectedForegroundColor: const Color(0xFF1D64D8),
            foregroundColor: const Color(0xFF374151),
            side: const BorderSide(color: Color(0xFFE1E8F2)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFE8F2FF),
          disabledColor: const Color(0xFFF3F6FA),
          side: const BorderSide(color: Color(0xFFE1E8F2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          labelStyle: const TextStyle(
            color: Color(0xFF374151),
            fontWeight: FontWeight.w800,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF3182F6),
          foregroundColor: Colors.white,
          extendedTextStyle: TextStyle(fontWeight: FontWeight.w800),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8F2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8F2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF3182F6), width: 1.5),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
