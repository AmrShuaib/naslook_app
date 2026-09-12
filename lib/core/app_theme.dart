import 'package:flutter/material.dart';

/// نظام «أبيض ونظيف»: خلفية بيضاء وصفوف مسطّحة بخطوط فاصلة رفيعة (على طريقة واتساب وسناب شات)،
/// والفيروزي لون العلامة للأفعال والعناصر النشطة، والمرجاني للأحداث والشارات.
class Joy {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  /// خلفيات خفيفة: الفقاعات الواردة، حبوب التاريخ، حقول البحث، الرقائق
  static const surface2 = Color(0xFFF2F2F7);
  static const text = Color(0xFF111111);
  static const textMuted = Color(0xFF6B7280);
  static const line = Color(0xFFE5E5EA);
  static const control = Color(0xFFC7C7CC);
  static const primary = Color(0xFF0A6E78);
  static const primaryOn = Color(0xFFFFFFFF);
  static const primarySoft = Color(0xFFE0F3F4);
  static const accent = Color(0xFFBF3A1E);
  static const accentOn = Color(0xFFFFFFFF);
  static const accentSoft = Color(0xFFFDEBE6);
  static const sun = Color(0xFFFFD66B);
  static const sunSoft = Color(0xFFFFF4D6);
  static const sunText = Color(0xFF5A4200);
  static const success = Color(0xFF1FA35A);
  static const warning = Color(0xFF875C0A);
  static const danger = Color(0xFFD23B3B);
  /// الفقاعة الصادرة: صبغة فاتحة من لون العلامة (كما الأخضر الفاتح في واتساب)
  static const bubbleOut = Color(0xFFDCF3EF);
  static const bubbleOutText = Color(0xFF0F2D30);
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
  /// الخطوط مضمّنة في التطبيق (pubspec.yaml → fonts/) ولا تُجلب من الإنترنت.
  static const bodyFont = 'Rubik';
  static const displayFont = 'BalooBhaijaan2';

  static ThemeData get light {
    // النص الافتراضي بوزن متوسط (500) بدل العادي (400) ليكون أوضح قليلاً
    final base = ThemeData(useMaterial3: true, fontFamily: bodyFont).textTheme.apply(bodyColor: Joy.text, displayColor: Joy.text);
    TextStyle? medium(TextStyle? t) => t?.copyWith(fontWeight: FontWeight.w500);
    final body = base.copyWith(
      bodyLarge: medium(base.bodyLarge), bodyMedium: medium(base.bodyMedium), bodySmall: medium(base.bodySmall),
      labelLarge: medium(base.labelLarge), labelMedium: medium(base.labelMedium), labelSmall: medium(base.labelSmall),
      titleSmall: medium(base.titleSmall),
    );
    const display = TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, color: Joy.text);
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
        backgroundColor: Joy.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Joy.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: Joy.line)),
        titleTextStyle: display.copyWith(fontSize: 21),
      ),
      cardTheme: CardThemeData(
        color: Joy.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Joy.line)),
      ),
      dividerTheme: const DividerThemeData(color: Joy.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Joy.surface2,
        hintStyle: const TextStyle(fontFamily: bodyFont, color: Joy.textMuted),
        labelStyle: const TextStyle(fontFamily: bodyFont, color: Joy.textMuted),
        helperStyle: const TextStyle(fontFamily: bodyFont, color: Joy.textMuted, fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Joy.primary, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Joy.primary,
          foregroundColor: Joy.primaryOn,
          minimumSize: const Size(44, 50),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600, fontSize: 15),
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
        style: TextButton.styleFrom(foregroundColor: Joy.primary, minimumSize: const Size(44, 44), textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Joy.surface2,
        selectedColor: Joy.primary,
        side: BorderSide.none,
        // ChipThemeData.labelStyle يحلّ محل نمط السمة كاملاً (لا يُدمج معه)، فلا بد من ذكر الخط صراحةً
        // وإلا سقط النص إلى Roboto الذي يُجلب من Google ويختفي حين تُحجب
        labelStyle: const TextStyle(fontFamily: bodyFont, color: Joy.text, fontSize: 13, fontWeight: FontWeight.w500),
        secondaryLabelStyle: const TextStyle(fontFamily: bodyFont, color: Joy.primaryOn, fontSize: 13, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Joy.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: bodyFont,
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? Joy.primary : Joy.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? Joy.primary : Joy.textMuted)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dialogTheme: DialogThemeData(backgroundColor: Joy.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Joy.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
      listTileTheme: const ListTileThemeData(iconColor: Joy.text),
      popupMenuTheme: PopupMenuThemeData(color: Joy.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
  }
}
