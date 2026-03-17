import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Shows a confirmation dialog when the user tries to leave a form with
/// unsaved changes.  Returns `true` to allow the pop, `false` to block it.
Future<bool> showDiscardChangesDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.discardChanges),
      content: const Text(
         'You have unsaved changes. Are you sure you want to leave?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.keepEditing),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: Text(l10n.discard),
        ),
      ],
    ),
  );
  return result ?? false;
}
