import 'package:flutter/material.dart';

import '../app/spacing.dart';
import '../enrolment/enrolment_copy.dart';
import '../widgets/screen_scaffold.dart';

/// Stands in for the real home screen until listings and bookings exist.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key, required this.roleLabel, required this.onSignOut});

  final String roleLabel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: EnrolmentCopy.welcome,
      icon: Icons.verified_user_outlined,
      children: [
        Text(roleLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.xl),
        OutlinedButton(onPressed: onSignOut, child: const Text(EnrolmentCopy.signOutLabel)),
      ],
    );
  }
}
