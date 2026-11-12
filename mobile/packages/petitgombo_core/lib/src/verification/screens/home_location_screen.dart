import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../widgets/message_banner.dart';
import '../capture.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import 'flow_scaffold.dart';

/// Home position step: one button, pressed at home.
class HomeLocationScreen extends ConsumerWidget {
  const HomeLocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(verificationControllerProvider);
    final failure = state.captureFailure;
    final denied = failure == CaptureFailure.permissionDenied ||
        failure == CaptureFailure.permissionDeniedForever;

    Future<void> record() async {
      final recorded = await ref.read(verificationControllerProvider.notifier).recordHome();
      if (recorded && context.mounted) Navigator.of(context).pop();
    }

    return FlowScaffold(
      title: VerificationCopy.homeTitle,
      banner: state.error == null
          ? null
          : MessageBanner(
              message: state.error!,
              actionLabel: denied ? VerificationCopy.openSettings : null,
              onAction: denied ? () => ref.read(positionReaderProvider).openSettings() : null,
            ),
      children: [
        Text(VerificationCopy.homeIntro, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        Text(VerificationCopy.homeBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.xl),
        BusyButton(label: VerificationCopy.recordPosition, onPressed: record, busy: state.sending),
      ],
    );
  }
}
