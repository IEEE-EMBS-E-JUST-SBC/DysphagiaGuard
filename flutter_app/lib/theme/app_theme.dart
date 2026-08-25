import 'package:flutter/material.dart';
import '../models/imu_sample.dart';

/// Central design tokens for DysphagiaGuard.
///
/// Two color systems, kept deliberately separate:
///  1. The RISK gradient (mint -> amber -> coral) — reserved ONLY for
///     swallow classification state. Never used decoratively.
///  2. The BRAND palette (violet/cyan/pink/gold) — used for structural
///     chrome (app bar, section headers, card accents, icons) so the
///     app feels vivid and alive without ever confusing "this is styling"
///     with "this is a health signal."
class AppColors {
  AppColors._();

  static const background = Color(0xFF0A1220);
  static const surface = Color(0xFF141B33);
  static const surfaceRaised = Color(0xFF1B2444);
  static const hairline = Color(0x24F4F1E8);

  static const textPrimary = Color(0xFFF6F4FB);
  static const textSecondary = Color(0xB3F6F4FB); // 70%
  static const textMuted = Color(0x70F6F4FB); // 44%

  // --- Risk signal colors (swallow classification only) ---
  static const mint = Color(0xFF2BE0A6); // normal
  static const amber = Color(0xFFFFC24B); // delayed / advisory
  static const coral = Color(0xFFFF5C7A); // aspiration risk
  static const slate = Color(0xFF7C89B8); // unknown / no data

  // --- Brand accent colors (chrome, cards, decoration) ---
  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFF472B6);
  static const gold = Color(0xFFFACC15);
  static const indigo = Color(0xFF6366F1);

  static Color forSwallowClass(SwallowClass c) {
    switch (c) {
      case SwallowClass.normal:
        return mint;
      case SwallowClass.delayedIncomplete:
        return amber;
      case SwallowClass.aspirationRisk:
        return coral;
      case SwallowClass.unknown:
        return slate;
    }
  }

  static LinearGradient get riskGradient => const LinearGradient(
        colors: [mint, amber, coral],
        stops: [0.0, 0.5, 1.0],
      );

  /// Vivid brand gradient for chrome: app bar, headers, primary buttons.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [violet, indigo, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// A rotating set of accent colors so cards/sections feel distinct
  /// rather than uniformly gray, without touching risk-signal meaning.
  static const List<Color> accentCycle = [cyan, pink, gold, violet];

  static Color accentFor(int index) => accentCycle[index % accentCycle.length];

  /// Soft glass-morphism style background for a colored card: a low-opacity
  /// tint of [color] layered over [surface].
  static BoxDecoration glassCard(Color color, {double borderOpacity = 0.35}) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withOpacity(0.16), surface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(borderOpacity), width: 1.4),
      boxShadow: [
        BoxShadow(color: color.withOpacity(0.22), blurRadius: 24, spreadRadius: -6),
      ],
    );
  }
}

class AppText {
  AppText._();

  static const _displayFamily = 'Roboto'; // rounded system default
  static const _monoFamily = 'RobotoMono';

  static const statusWord = TextStyle(
    fontFamily: _displayFamily,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
    color: AppColors.textPrimary,
  );

  static const metricValue = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const metricLabel = TextStyle(
    fontFamily: _displayFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: AppColors.textSecondary,
  );

  static const body = TextStyle(
    fontFamily: _displayFamily,
    fontSize: 14,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const caption = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 11,
    color: AppColors.textMuted,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

