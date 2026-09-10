import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// نظام «فرح وبهجة»: كريمي مشمس، فيروزي للأفعال، مرجاني للأحداث، أصفر شمسي.
/// كل الأزواج مقاسة بنِسَب تباين WCAG ≥ 4.5:1.
class Joy {
  static const bg = Color(0xFFFFF6E8);
  static const surface = Color(0xFFFFFDF9);
  static const surface2 = Color(0xFFFFECD9);
  static const text = Color(0xFF2B2420);
  static const textMuted = Color(0xFF6A5B52);
  static const line = Color(0xFFF0DCC6);
  static const control = Color(0xFF98847A);
  static const primary = Color(0xFF0A6E78);
  static const primaryOn = Color(0xFFF3FDFF);
  static const primarySoft = Color(0xFFD6F3F4);
  static const accent = Color(0xFFBF3A1E);
  static const accentOn = Color(0xFFFFF6F1);
  static const accentSoft = Color(0xFFFFE8DF);
  static const sun = Color(0xFFFFD66B);
  static const sunSoft = Color(0xFFFFF0C2);
  static const sunText = Color(0xFF5A4200);
  static const success = Color(0xFF2C7A4B);
  static const warning = Color(0xFF875C0A);
  static const danger = Color(0xFFB8323E);
  static const bubbleOut = Color(0xFFFFE6A8);
  static const bubbleOutText = Color(0xFF3B2E0C);
  static const avatars = [
    Color(0xFFFFB09F), Color(0xFF9EE0CC), Color(0xFFA9D3FF),
    Color(0xFFD4BDFF), Color(0xFFFFDF7A), Color(0xFFFFB9D6),
  ];

  static Color avatarFor(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatars[h % avatars.length];
  }
}

class AppTheme {
  static ThemeData get light {
    final body = GoogleFonts.rubikTextTheme().apply(bodyColor: Joy.text, displayColor: Joy.text);
    final display = GoogleFonts.balooBhaijaan2(fontWeight: FontWeight.w700, color: Joy.text);
    final scheme = ColorScheme.fromSeed(
      seedColor: Joy.primary,
      primary: Joy.primary,
      onPrimary: Joy.primaryOn,
      secondary: Joy.accent,
      onSecondary: Joy.accentOn,
      surface: Joy.surface,
      onSurface: Joy.text,
      error: Joy.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Joy.bg,
      textTheme: body.copyWith(
        headlineSmall: display.copyWith(fontSize: 24),
        titleLarge: display.copyWith(fontSize: 22),
        titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
        bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.6),
        bodySmall: body.bodySmall?.copyWith(fontSize: 13, color: Joy.textMuted, height: 1.5),
        labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Joy.bg,
        foregroundColor: Joy.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display.copyWith(fontSize: 22),
      ),
      cardTheme: CardThemeData(
        color: Joy.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Joy.line)),
      ),
      dividerTheme: const DividerThemeData(color: Joy.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Joy.bg,
        hintStyle: const TextStyle(color: Joy.textMuted),
        labelStyle: const TextStyle(color: Joy.textMuted),
        helperStyle: const TextStyle(color: Joy.textMuted, fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Joy.control)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Joy.control)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Joy.primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Joy.primary,
          foregroundColor: Joy.primaryOn,
          minimumSize: const Size(44, 50),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.rubik(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Joy.primary,
          minimumSize: const Size(44, 44),
          side: const BorderSide(color: Joy.control),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Joy.primary, minimumSize: const Size(44, 44), textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Joy.surface,
        selectedColor: Joy.primary,
        side: const BorderSide(color: Joy.control),
        labelStyle: const TextStyle(color: Joy.text, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Joy.primaryOn, fontSize: 13, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Joy.surface,
        indicatorColor: Joy.primarySoft,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? Joy.primary : Joy.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? Joy.primary : Joy.textMuted)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dialogTheme: DialogThemeData(backgroundColor: Joy.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Joy.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
    );
  }
}
