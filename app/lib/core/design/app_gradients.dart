import 'package:flutter/material.dart';
import 'app_colors.dart';

/// NexaDrive gradient family.
///
/// Gradients are a *family*, not a scatter of one-offs. Five signed families
/// (Cloud, Secure, Storage, Media, Success) each derive from two calm,
/// analogous One UI hues. Use the vivid face for branded hero/moment surfaces
/// (media artwork, special empty states, storage hero) and the soft face for
/// quiet tonal reinforcement behind ordinary surfaces. Never rainbow, never
/// neon, never on every card — a gradient guides attention.
abstract final class AppGradients {
  // ------------------------------------------------------------- palette
  /// Sky — the light end of the cloud family.
  static const Color sky = Color(0xFF78C9F7);

  /// Azure — transition tone toward the accent.
  static const Color azure = Color(0xFF2FA8E6);

  /// Ocean — the NexaDrive signature accent.
  static const Color ocean = Color(0xFF0B87D0);

  /// Indigo — deep secure tone.
  static const Color indigo = Color(0xFF5F6FEA);

  /// Teal — storage tone.
  static const Color teal = Color(0xFF32C0B0);

  /// Mint — bright success tone.
  static const Color mint = Color(0xFF5AD9B4);

  /// Violet — media tone.
  static const Color violet = Color(0xFF9672F0);

  /// Pine — deep success tone.
  static const Color pine = Color(0xFF24A66E);

  // -------------------------------------------------------------- family

  static const Map<GradientFamily, (Color, Color)> _pairs = {
    GradientFamily.cloud: (sky, ocean),
    GradientFamily.secure: (ocean, indigo),
    GradientFamily.storage: (teal, ocean),
    GradientFamily.media: (violet, ocean),
    GradientFamily.success: (mint, pine),
  };

  /// Vivid, opaque gradient — for surfaces that ARE the gradient.
  static LinearGradient vivid(GradientFamily family) => _build(family, null);

  /// Soft, translucent gradient meant to sit over a solid surface — for
  /// tonal hero areas and reinforced focus blocks (not for text underlays).
  static LinearGradient soft(GradientFamily family, Brightness brightness) {
    final alpha = brightness == Brightness.dark ? 0.20 : 0.13;
    return _build(family, alpha);
  }

  /// Ambient page wash — a whisper of sky at the top of the viewing area,
  /// fading to the page background. Use only as a background decoration.
  static LinearGradient pageWash(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.45],
        colors: [
          AppColors.accentDark.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0.0, 0.5],
      colors: [sky.withValues(alpha: 0.18), Colors.transparent],
    );
  }

  /// The storage hero face: diagonal cloud→ocean, calm and personal-cloud-like.
  static LinearGradient storageHero(Brightness brightness) =>
      vivid(GradientFamily.cloud);

  static LinearGradient _build(GradientFamily family, double? alpha) {
    final (beginColor, endColor) = _pairs[family]!;
    final colors = alpha == null
        ? [beginColor, endColor]
        : [beginColor.withValues(alpha: alpha), endColor.withValues(alpha: alpha)];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }
}

enum GradientFamily { cloud, secure, storage, media, success }