import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../core/models/compatibility_result.dart';

/// Paleta e tokens visuais inspirados na Steam Big Picture: fundo quase preto
/// azulado, superfícies em camadas, azul Steam como destaque.
class PH {
  static const bg = Color(0xFF0A0D12);
  static const bg2 = Color(0xFF10151C);
  static const surface = Color(0xFF181E27);
  static const surfaceHi = Color(0xFF222A36);
  static const stroke = Color(0x1FFFFFFF);
  static const accent = Color(0xFF1A9FFF);
  static const accentSoft = Color(0xFF66C0F4);
  static const text = Color(0xFFE8EDF2);
  static const textDim = Color(0xFF8D99A6);
  static const textFaint = Color(0xFF5C6773);
  static const green = Color(0xFF5BC236);
  static const yellow = Color(0xFFF2B533);
  static const red = Color(0xFFE5484D);

  static const radius = 10.0;
  static const radiusLg = 16.0;

  static Color compat(CompatLevel l) => switch (l) {
        CompatLevel.compatible => green,
        CompatLevel.partial => yellow,
        CompatLevel.incompatible => red,
        CompatLevel.unknown => textFaint,
      };

  /// Gradiente de destaque usado em botões primários (verde "Jogar" da Steam).
  static const playGradient = LinearGradient(colors: [Color(0xFF75B022), Color(0xFF588A1B)]);
  static const installGradient = LinearGradient(colors: [Color(0xFF47BFFF), Color(0xFF1A73E8)]);
  static const updateGradient = LinearGradient(colors: [Color(0xFFF2B533), Color(0xFFD98E04)]);

  /// Escala de layout: telas grandes (TV/desktop) ganham elementos maiores.
  static double scale(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final byWidth = w >= 1800 ? 1.25 : w >= 1200 ? 1.0 : w >= 800 ? 0.9 : 0.8;
    // Celular deitado tem pouca altura (~410pt): a prateleira (título + capa
    // em retrato) precisa caber entre a barra superior e a de dicas.
    final byHeight = ((size.height - 260) / 230).clamp(0.55, 1.25);
    return byWidth < byHeight ? byWidth : byHeight;
  }

  static bool compact(BuildContext context) => MediaQuery.sizeOf(context).width < 700;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: PH.accent, brightness: Brightness.dark).copyWith(
    primary: PH.accent,
    secondary: PH.accentSoft,
    surface: PH.surface,
    onSurface: PH.text,
    error: PH.red,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: PH.bg,
    canvasColor: PH.bg,
    focusColor: PH.accent.withValues(alpha: 0.25),
    hoverColor: Colors.white.withValues(alpha: 0.05),
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: PH.text, displayColor: PH.text).copyWith(
          displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
    dividerTheme: const DividerThemeData(color: PH.stroke, thickness: 1),
    cardTheme: const CardThemeData(color: PH.surface, elevation: 0, margin: EdgeInsets.zero),
    dialogTheme: const DialogThemeData(backgroundColor: PH.surface),
    snackBarTheme: const SnackBarThemeData(backgroundColor: PH.surfaceHi, contentTextStyle: TextStyle(color: PH.text)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PH.surfaceHi,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(PH.radius), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PH.radius),
        borderSide: const BorderSide(color: PH.accent, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : PH.textDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? PH.accent : PH.surfaceHi),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Permite arrastar listas com mouse no desktop (cards horizontais).
class PHScrollBehavior extends MaterialScrollBehavior {
  const PHScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
