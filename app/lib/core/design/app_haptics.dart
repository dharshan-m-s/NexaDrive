import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's only haptic vocabulary.
///
/// Haptics confirm state changes that are otherwise silent — entering or
/// leaving selection, toggling an item, a deliberate long press — never every
/// tap. Calls are fire-and-forget and stay silent on platforms without a
/// haptic engine (web and desktop).
abstract final class AppHaptics {
  /// True where the platform exposes a haptic engine.
  static bool get _supported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          true,
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows =>
          false,
      };

  /// A light detent: selecting, toggling, moving between tabs.
  static void selection() {
    if (!_supported) return;
    unawaited(HapticFeedback.selectionClick());
  }

  /// A light impact: a long press that enters selection mode.
  static void impact() {
    if (!_supported) return;
    unawaited(HapticFeedback.lightImpact());
  }

  /// A firmer impact for destructive or completed actions.
  static void success() {
    if (!_supported) return;
    unawaited(HapticFeedback.mediumImpact());
  }
}
