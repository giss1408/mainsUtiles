import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../widgets/screen_scaffold.dart';
import '../enrolment_copy.dart';

/// A closed application: refused, locked or expired. The only way on is a new one.
class OutcomeScreen extends StatelessWidget {
  const OutcomeScreen({
    super.key,
    required this.title,
    required this.onStartOver,
    this.body,
    this.banner,
  });

  final String title;
  final String? body;
  final VoidCallback onStartOver;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: title,
      icon: Icons.info_outline,
      banner: banner,
      children: [
        if (body != null) Text(body!, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.xl),
        FilledButton(onPressed: onStartOver, child: const Text(EnrolmentCopy.startOverLabel)),
      ],
    );
  }
}
