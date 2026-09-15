import 'package:flutter/material.dart';

/// NexaDrive shadow prescriptions.
///
/// One UI visual rule: shadows stay *soft and restrained* — separation comes
/// mostly from tone, shadow only carries the sheet/dialog/menu layer.
/// Shadows are brightness-aware (white-light in dark mode, neutral in light).
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  /// LEVEL 1 — resting surface over the page background.
  static List<BoxShadow> level1(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x0D, dark: 0x0F),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  /// LEVEL 2 — grouped panel / hovered card.
  static List<BoxShadow> level2(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x14, dark: 0x1A),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  /// LEVEL 3 — floating controls, menus, popovers.
  static List<BoxShadow> level3(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x1F, dark: 0x24),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ];

  /// LEVEL 4 — dialogs and modal sheets.
  static List<BoxShadow> level4(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x29, dark: 0x2E),
          blurRadius: 48,
          offset: const Offset(0, 16),
        ),
      ];

  /// A top-weighted shadow for bottom sheets (light catches the top edge).
  static List<BoxShadow> sheet(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x1A, dark: 0x1F),
          blurRadius: 44,
          offset: const Offset(0, -8),
        ),
      ];

  static Color shadow(Brightness b,
          {required int light, required int dark}) =>
      Color(b == Brightness.dark ? (dark << 24) | 0xFFFFFF : (light << 24));
}