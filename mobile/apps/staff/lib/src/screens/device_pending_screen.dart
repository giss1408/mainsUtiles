import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_copy.dart';

class DevicePendingScreen extends StatelessWidget {
  const DevicePendingScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: StaffCopy.devicePendingTitle,
      icon: Icons.hourglass_top,
      children: [
        Text(StaffCopy.devicePending, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Gaps.xl),
        FilledButton(onPressed: onRetry, child: const Text(StaffCopy.retry)),
      ],
    );
  }
}
