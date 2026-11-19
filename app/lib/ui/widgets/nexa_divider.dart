import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';

/// Material 3 divider for grouped content surfaces.
class NexaDivider extends StatelessWidget {
  final double indent;
  final double endIndent;
  final double thickness;
  final Color? color;

  const NexaDivider({
    super.key,
    this.indent = 0,
    this.endIndent = 0,
    this.thickness = 1,
    this.color,
  });

  /// Divider that skips leading icon (for grouped list tiles with icons).
  const NexaDivider.inset({
    super.key,
    this.endIndent = AppDimens.pageMargin,
    this.thickness = 1,
    this.color,
  }) : indent =
            AppDimens.pageMargin + AppDimens.iconTileLarge + AppDimens.space12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(
      color: color ?? scheme.outlineVariant,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      height: 0,
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
    this.height = AppDimens.space24,
    this.thickness = 1,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: VerticalDivider(
        color: color ?? scheme.outlineVariant,
        thickness: thickness,
        indent: 0,
        endIndent: 0,
      ),
    );
  }
}
