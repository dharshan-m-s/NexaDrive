import 'package:flutter/material.dart';
import '../../core/design/app_dimensions.dart';

/// Shared page controls that every pushed screen needs.
///
/// Buttons deliberately do *not* live here: `app_theme.dart` already themes
/// `FilledButton` / `OutlinedButton` / `TextButton` centrally (pill shape,
/// minimum touch target, type scale), so a wrapper would only duplicate it.
/// These are the two pieces that were being re-declared privately on each
/// screen, which is what let them drift.
abstract final class OneUiControls {}

/// Standard back affordance for a pushed One UI page.
///
/// Uses `maybePop` so it is safe on a root route, and pulls its label from
/// `MaterialLocalizations` so it is localised rather than hard-coded "Back".
class OneUiBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const OneUiBackButton(
      {super.key, this.onPressed, this.icon = Icons.arrow_back_rounded});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: Icon(icon),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppDimens.touchTarget,
        minHeight: AppDimens.touchTarget,
      ),
    );
  }
}

/// Neutral loading block in the One UI surface language.
///
/// A bare `CircularProgressIndicator` centred in the viewport reads as
/// unfinished; this reserves a fixed block so a loading page does not reflow
/// when the content arrives.
///
/// Named `...LoadingBlock` rather than `OneUiProgressTile` on purpose: the
/// latter is the *determinate* progress row used by Transfers, and overloading
/// that name for an indeterminate spinner was already a source of confusion.
class OneUiLoadingBlock extends StatelessWidget {
  final String? label;
  final double inset;

  const OneUiLoadingBlock(
      {super.key, this.label, this.inset = AppDimens.space48});

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: AppDimens.space24,
      height: AppDimens.space24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.primary,
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: inset),
      child: Center(
        child: label == null
            ? spinner
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  spinner,
                  const SizedBox(height: AppDimens.space12),
                  Text(label!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
      ),
    );
  }
}
