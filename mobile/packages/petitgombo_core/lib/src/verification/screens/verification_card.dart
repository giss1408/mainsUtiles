import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../widgets/ui_kit.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import '../verification_models.dart';
import 'checklist_screen.dart';

/// Tells a jobber how far the account verification is and opens the checklist.
/// Renders nothing until a checklist is known, so the screen around it never waits.
class VerificationCard extends ConsumerWidget {
  const VerificationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(verificationControllerProvider).checklist;
    if (checklist == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final verified = checklist.verified;
    final steps = {
      'identity': checklist.identity,
      'guarantor': checklist.guarantor,
      'trusted_contact': checklist.trustedContact,
      'briefing': checklist.briefing,
    };
    final done =
        checklist.required.where((name) => steps[name]?.status == StepStatus.confirmed).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.lg),
      child: AppCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChecklistScreen(onBack: () => Navigator.of(context).pop()),
          ),
        ),
        child: Row(
          children: [
            IconTile(icon: verified ? Icons.verified_user : Icons.verified_user_outlined),
            const SizedBox(width: Gaps.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verified ? VerificationCopy.cardVerified : VerificationCopy.cardTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (!verified) ...[
                    const SizedBox(height: Gaps.xs),
                    Text(
                      VerificationCopy.cardProgress(done, checklist.required.length),
                      style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
