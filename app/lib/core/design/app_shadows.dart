import 'package:flutter/material.dart';

/// NexaDrive elevation — Material 3 tonal/depth model.
///
/// Elevation is carried by tonal surface roles first and a restrained shadow
/// second. The five presets below follow Material's level-1..level-5 geometry;
/// dark surfaces lean on tone rather than darker shadows.
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  static List<BoxShadow> level1(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x26, dark: 0x40),
          blurRadius: 2,
          spreadRadius: -1,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> level2(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x26, dark: 0x40),
          blurRadius: 4,
          spreadRadius: -1,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> level3(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x26, dark: 0x40),
          blurRadius: 8,
          spreadRadius: -2,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> level4(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x26, dark: 0x40),
          blurRadius: 12,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> level5(Brightness brightness) => [
        BoxShadow(
          color: shadow(brightness, light: 0x26, dark: 0x40),
          blurRadius: 16,
          spreadRadius: -3,
          offset: const Offset(0, 8),
        ),
      ];

  /// Modal sheets use level 3 in Material 3.
  static List<BoxShadow> sheet(Brightness brightness) => level3(brightness);

  static List<BoxShadow> material1(Brightness brightness) => level1(brightness);

  static Color shadow(Brightness b, {required int light, required int dark}) =>
      Color(b == Brightness.dark ? (dark << 24) | 0x000000 : (light << 24));
}

/// Compatibility alias over [AppShadows].
typedef NexaShadows = AppShadows;
