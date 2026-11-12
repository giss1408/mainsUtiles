import 'package:flutter/material.dart';

import '../app/spacing.dart';
import '../app/theme.dart';

/// A problem the user can act on: icon and text, never colour alone.
class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Gaps.md),
        decoration: BoxDecoration(
          color: AppColors.warningSurface,
          border: Border.all(color: AppColors.warning),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppColors.warning),
                const SizedBox(width: Gaps.sm),
                Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
              ],
            ),
            if (actionLabel != null && onAction != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
          ],
        ),
      ),
    );
  }
}
