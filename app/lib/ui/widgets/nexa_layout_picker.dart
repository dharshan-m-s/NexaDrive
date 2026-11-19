import 'package:flutter/material.dart';

import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';

/// Shared grid-density vocabulary for galleries and file browsers.
///
/// Column count is a user preference, not a screen-specific styling choice:
/// Files and Photos use the same range, labels and persistence semantics.
abstract final class NexaGridLayout {
  static const int minColumns = 1;
  static const int maxColumns = 8;

  static int clamp(int value) => value.clamp(minColumns, maxColumns).toInt();

  static String label(int columns) =>
      columns == 1 ? '1 column' : '$columns columns';
}

/// Presents the same calm, direct layout control everywhere a grid appears.
///
/// Density is a continuous slider rather than a row of column buttons: dragging
/// towards "more" behaves like zooming in on the grid. Pinching the grid does
/// the same thing directly; this dialog is the accessible, precise equivalent.
Future<int?> showNexaGridLayoutPicker({
  required BuildContext context,
  required int columns,
  String title = 'Layout',
  String subtitle = 'Choose how much fits on screen.',
}) async {
  var draft = NexaGridLayout.clamp(columns);
  final scheme = Theme.of(context).colorScheme;

  final selected = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              subtitle,
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grid density',
                  style: AppTextStyle.labelMedium.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  NexaGridLayout.label(draft),
                  style: AppTextStyle.title3.copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space8),
            Semantics(
              label: 'Grid density',
              child: Slider(
                value: draft.toDouble(),
                min: NexaGridLayout.minColumns.toDouble(),
                max: NexaGridLayout.maxColumns.toDouble(),
                divisions:
                    NexaGridLayout.maxColumns - NexaGridLayout.minColumns,
                label: NexaGridLayout.label(draft),
                onChanged: (value) =>
                    setDialogState(() => draft = value.round()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.space12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.zoom_out_rounded,
                    size: AppDimens.iconSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppDimens.space6),
                  Text(
                    'Fewer',
                    style: AppTextStyle.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'More',
                    style: AppTextStyle.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space6),
                  Icon(
                    Icons.zoom_in_rounded,
                    size: AppDimens.iconSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.space20),
            Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: AppDimens.iconSmall,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Text(
                    'Pinching the grid changes density directly.',
                    style: AppTextStyle.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, draft),
          child: const Text('Apply'),
        ),
      ],
    ),
  );

  return selected == null ? null : NexaGridLayout.clamp(selected);
}
