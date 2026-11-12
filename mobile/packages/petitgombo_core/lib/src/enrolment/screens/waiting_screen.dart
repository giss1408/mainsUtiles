import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../widgets/screen_scaffold.dart';
import '../enrolment_copy.dart';

/// Shown while staff review the application.
class WaitingScreen extends StatelessWidget {
  const WaitingScreen({
    super.key,
    required this.title,
    required this.body,
    required this.onRefresh,
    this.reason,
    this.banner,
  });

  final String title;
  final String body;
  final String? reason;
  final VoidCallback onRefresh;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: title,
      icon: Icons.hourglass_top,
      banner: banner,
      children: [
        Text(body, style: theme.textTheme.bodyLarge),
        if (reason != null) ...[
          const SizedBox(height: Gaps.sm),
          Text(reason!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gaps.xl),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text(EnrolmentCopy.refreshLabel),
        ),
      ],
    );
  }
}
