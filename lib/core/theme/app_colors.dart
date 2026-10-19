import 'package:flutter/material.dart';

/// Centralized Color Theme System — exact port of `src/theme/colors.ts`.
/// All widgets must use these colors instead of hardcoded values.
class AppColors {
  AppColors._();

  static bool isDark = true;

  // ===== PRIMARY THEME COLORS =====
  static const primary = Color(0xFF4CAF50);
  static const primaryDark = Color(0xFF45A049);
  static const primaryLight = Color.fromRGBO(76, 175, 80, 0.1);
  static const primaryAlpha = Color.fromRGBO(76, 175, 80, 0.2);

  // ===== SECONDARY THEME COLORS =====
  static const secondary = Color(0xFFFF6B6B);
  static const secondaryDark = Color(0xFFE55A5A);
  static const secondaryLight = Color.fromRGBO(255, 107, 107, 0.1);
  static const secondaryAlpha = Color.fromRGBO(255, 107, 107, 0.2);

  // ===== ACCENT THEME COLORS =====
  static const accent = Color(0xFFFFB74D);
  static const accentDark = Color(0xFFFF9800);
  static const accentLight = Color.fromRGBO(255, 183, 77, 0.1);
  static const accentAlpha = Color.fromRGBO(255, 183, 77, 0.2);

  // ===== TEXT COLORS =====
  static Color get text => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF142424);
  static Color get textSecondary => isDark ? const Color(0xFFA0D8D8) : const Color(0xFF4D6E6E);
  static Color get textMuted => isDark ? const Color(0xFF666666) : const Color(0xFF889B9B);
  static const textDark = Color(0xFF333333);
  static const textLight = Color(0xFFF5F5F5);

  /// Slate-900 heading on light surfaces / white on dark
  /// (Tailwind slate-900 #0F172A used across desktop views).
  static Color get heading =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A);

  /// Muted/hint slate text pair used in desktop chrome.
  static Color get textHint =>
      isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  /// Slate-100 / dark card fill pair for light-mode card surfaces.
  static Color get cardTint => isDark
      ? const Color.fromRGBO(255, 255, 255, 0.05)
      : const Color(0xFFF1F5F9);

  // ===== BACKGROUND COLORS =====
  static Color get background => isDark ? const Color.fromRGBO(0, 0, 0, 0.5) : const Color.fromRGBO(0, 0, 0, 0.3);
  static Color get backgroundDark => isDark ? const Color(0xFF0A1F1F) : const Color(0xFFF4F7F6);
  static const backgroundLight = Color(0xFFF8F9FA);

  /// Smooth vertical theme background gradient with liquid glass translucency
  static LinearGradient backgroundGradient(bool isDark) => isDark
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF081E1E).withValues(alpha: 0.82), // Deep emerald-teal atmosphere
            const Color(0xFF051515).withValues(alpha: 0.86), // Midnight slate
            const Color(0xFF030D0D).withValues(alpha: 0.90), // Obsidian baseline
          ],
          stops: const [0.0, 0.45, 1.0],
        )
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF0FDF4).withValues(alpha: 0.82), // Fresh soft mint sheen
            const Color(0xFFF7FAF8).withValues(alpha: 0.86), // Crisp porcelain
            const Color(0xFFEDF4F2).withValues(alpha: 0.90), // Silky sage mist
          ],
          stops: const [0.0, 0.4, 1.0],
        );
  static const primaryBackground = Color.fromRGBO(76, 175, 80, 0.1);
  static const errorBackground = Color.fromRGBO(255, 107, 107, 0.1);
  static Color get surface => isDark ? const Color.fromRGBO(255, 255, 255, 0.05) : const Color(0xFFFFFFFF);
  static Color get surfaceHover => isDark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color(0xFFEDF2F2);
  static Color get surfaceBorder => isDark ? const Color.fromRGBO(255, 255, 255, 0.1) : const Color(0xFFDFE6E6);

  // ===== STATUS COLORS =====
  static const success = Color(0xFF4CAF50);
  static const successLight = Color.fromRGBO(76, 175, 80, 0.1);
  static const error = Color(0xFFFF6B6B);
  static const errorLight = Color.fromRGBO(255, 107, 107, 0.1);
  static const warning = Color(0xFFFFA726);
  static const warningLight = Color.fromRGBO(255, 167, 38, 0.1);
  static const info = Color(0xFF2196F3);
  static const infoLight = Color.fromRGBO(33, 150, 243, 0.1);

  // ===== BUTTON COLORS =====
  static const buttonPrimary = Color(0xFF4CAF50);
  static const buttonPrimaryText = Color(0xFFFFFFFF);
  static const buttonSecondary = Color.fromRGBO(255, 255, 255, 0.1);
  static const buttonSecondaryText = Color(0xFFFFFFFF);
  static const buttonDanger = Color(0xFFFF6B6B);
  static const buttonDangerText = Color(0xFFFFFFFF);
  static const buttonDisabled = Color(0xFF666666);
  static const buttonDisabledText = Color(0xFF999999);

  // ===== GRADIENT COLORS =====
  static const gradientPrimary = [Color(0xFF4CAF50), Color(0xFF45A049)];
  static List<Color> get gradientSecondary => isDark
      ? const [Color.fromRGBO(255, 255, 255, 0.1), Color.fromRGBO(255, 255, 255, 0.05)]
      : const [Color(0xFFFFFFFF), Color(0xFFF7FAFA)];
  static const gradientDanger = [
    Color.fromRGBO(255, 107, 107, 0.2),
    Color.fromRGBO(255, 107, 107, 0.1),
  ];
  static List<Color> get gradientBackground => isDark
      ? const [Color(0xFF0A1F1F), Color(0xFF1A3A3A)]
      : const [Color(0xFFF4F7F6), Color(0xFFE8EFEF)];

  // ===== BORDER COLORS =====
  static Color get border => isDark ? const Color.fromRGBO(255, 255, 255, 0.1) : const Color(0xFFDCE3E3);
  static Color get borderLight => isDark ? const Color.fromRGBO(255, 255, 255, 0.05) : const Color(0xFFE9EEEE);
  static Color get borderDark => isDark ? const Color.fromRGBO(255, 255, 255, 0.2) : const Color(0xFFCCD5D5);
  static const borderFocus = Color(0xFF4CAF50);

  // ===== SHADOW COLORS =====
  static Color get shadow => isDark ? const Color.fromRGBO(0, 0, 0, 0.3) : const Color.fromRGBO(0, 0, 0, 0.06);
  static Color get shadowLight => isDark ? const Color.fromRGBO(0, 0, 0, 0.1) : const Color.fromRGBO(0, 0, 0, 0.03);
  static Color get shadowDark => isDark ? const Color.fromRGBO(0, 0, 0, 0.5) : const Color.fromRGBO(0, 0, 0, 0.12);

  // ===== ICON COLORS =====
  static Color get icon => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF142424);
  static Color get iconSecondary => isDark ? const Color(0xFFA0D8D8) : const Color(0xFF4D6E6E);
  static Color get iconMuted => isDark ? const Color(0xFF666666) : const Color(0xFF889B9B);

  // ===== SURFACES / SHEETS =====
  static Color get sheetBackground => isDark ? const Color(0xFF061818) : const Color(0xFFFFFFFF);
  static Color get cardBackground => isDark ? const Color(0xFF061818) : const Color(0xFFFFFFFF);
  static Color get dropdownBackground => isDark ? const Color(0xFF061818) : const Color(0xFFFFFFFF);

  // ===== TRANSPARENCY LEVELS =====
  static const transparent = Colors.transparent;
  static const overlay = Color.fromRGBO(0, 0, 0, 0.5);
  static const overlayLight = Color.fromRGBO(0, 0, 0, 0.3);
  static const overlayDark = Color.fromRGBO(0, 0, 0, 0.7);

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'success':
      case 'paid':
      case 'completed':
      case 'active':
      case 'confirmed':
        return success;
      case 'error':
      case 'failed':
      case 'cancelled':
      case 'inactive':
      case 'overdue':
        return error;
      case 'warning':
      case 'pending':
      case 'processing':
      case 'partial':
      case 'in-progress':
        return warning;
      case 'info':
      case 'draft':
        return info;
      default:
        return textSecondary;
    }
  }

  static Color statusBackground(String status) {
    switch (status.toLowerCase()) {
      case 'success':
      case 'paid':
      case 'completed':
      case 'active':
      case 'confirmed':
        return successLight;
      case 'error':
      case 'failed':
      case 'cancelled':
      case 'inactive':
      case 'overdue':
        return errorLight;
      case 'warning':
      case 'pending':
      case 'processing':
      case 'partial':
      case 'in-progress':
        return warningLight;
      case 'info':
      case 'draft':
        return infoLight;
      default:
        return surface;
    }
  }
}
