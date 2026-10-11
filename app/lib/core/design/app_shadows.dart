import 'package:flutter/material.dart';

/// NexaDrive shadow prescriptions.
///
/// THE REFERENCE: Apple's depth model. Hierarchy comes almost entirely from
/// layered tone and translucency; shadow only carries genuinely floating
/// surfaces (control clusters, sheets, popovers). Shadows are soft, tightly
/// offset and low-opacity, and dark mode leans on a hairline border as much as
/// on the shadow.
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  /// LEVEL 1 — resting surface over the page background. Nearly flat.
  static List<BoxShadow> level1(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x0A, dark: 0x1A),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  /// LEVEL 2 — grouped panel / hovered card.
  static List<BoxShadow> level2(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x12, dark: 0x24),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  /// LEVEL 3 — floating controls, menus, popovers.
  static List<BoxShadow> level3(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x1C, dark: 0x33),
          blurRadius: 28,
          offset: const Offset(0, 8),
        ),
      ];

  /// LEVEL 4 — dialogs and modal sheets.
  static List<BoxShadow> level4(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x24, dark: 0x40),
          blurRadius: 44,
          offset: const Offset(0, 16),
        ),
      ];

  /// A top-weighted shadow for bottom sheets (light catches the top edge).
  static List<BoxShadow> sheet(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x1A, dark: 0x33),
          blurRadius: 40,
          offset: const Offset(0, -8),
        ),
      ];

  /// Material's small elevation preset, quietly tuned.
  static List<BoxShadow> material1(Brightness brightness) => level1(brightness);

  static Color shadow(Brightness b, {required int light, required int dark}) =>
      Color(b == Brightness.dark ? (dark << 24) | 0x000000 : (light << 24));
}

/// iOS-named alias for [AppShadows].
typedef NexaShadows = AppShadows;
