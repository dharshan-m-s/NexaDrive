import 'package:flutter/material.dart';

/// Reversible-action feedback that stays within the app's SnackBar language.
///
/// Undo is deliberately a quiet text action: it must not turn a destructive
/// moment into a celebration, and it must remain reachable from the keyboard
/// and screen readers through the standard SnackBar semantics.
abstract final class NexaUndo {
  static void show(
    BuildContext context,
    String message, {
    String actionLabel = 'Undo',
    required VoidCallback onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          action: SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
  }
}
