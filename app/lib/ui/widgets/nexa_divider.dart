import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';

/// Subtle divider (iOS-style).
class NexaDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final double thickness;
  final Color? color;

  const NexaDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.thickness = 0.5,
    this.color,
  });

  /// Divider that skips leading icon (for grouped list tiles with icons).
  const NexaDivider.inset({
    super.key,
    this.endIndent = AppDimens.pageMargin,
    this.thickness = 0.5,
    this.color,
  }) : indent =
            AppDimens.pageMargin + AppDimens.iconTileLarge + AppDimens.space12;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Divider(
      color: color ?? AppColors.separatorFor(brightness),
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      height: 1,
    );
  }
}

/// Vertical divider.
class NexaVerticalDivider extends StatelessWidget {
  final double height;
  final double thickness;
  final Color? color;

  const NexaVerticalDivider({
    super.key,
    this.height = 24,
    this.thickness = 0.5,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      height: height,
      child: VerticalDivider(
        color: color ?? AppColors.separatorFor(brightness),
        thickness: thickness,
        indent: 0,
        endIndent: 0,
      ),
    );
  }
}
