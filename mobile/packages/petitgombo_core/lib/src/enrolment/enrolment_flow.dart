import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_scaffold.dart';
import 'enrolment_copy.dart';
import 'enrolment_state.dart';
import 'screens/code_entry_screen.dart';
import 'screens/outcome_screen.dart';
import 'screens/phone_entry_screen.dart';
import 'screens/waiting_screen.dart';

/// Shows the screen that matches the enrolment state.
class EnrolmentFlow extends ConsumerWidget {
  const EnrolmentFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(enrolmentControllerProvider);
    final controller = ref.read(enrolmentControllerProvider.notifier);
    final copy = EnrolmentCopy.forRole(ref.watch(appRoleProvider));

    // A failure keeps the screen the user was on and adds a message above it.
    Widget? banner;
    var shown = state;
    if (state is EnrolmentFailure) {
      shown = state.previous;
      banner = MessageBanner(
        message: state.message,
        actionLabel: shown is EnrolmentInitial ? null : EnrolmentCopy.retryLabel,
        onAction: controller.refresh,
      );
    }

    // Keys keep each screen's typed input when only the banner changes.
    return switch (shown) {
      EnrolmentInitial() || EnrolmentSubmitting() => PhoneEntryScreen(
          key: const ValueKey('phone'),
          copy: copy,
          busy: shown is EnrolmentSubmitting,
          banner: banner,
          onSubmit: controller.submitPhone,
        ),
      EnrolmentPending(:final responseHours) => WaitingScreen(
          key: const ValueKey('pending'),
          title: EnrolmentCopy.pendingTitle,
          body: EnrolmentCopy.pendingBody(responseHours),
          banner: banner,
          onRefresh: controller.refresh,
        ),
      EnrolmentHeld(:final reason) => WaitingScreen(
          key: const ValueKey('held'),
          title: EnrolmentCopy.pendingTitle,
          body: copy.heldBody,
          reason: reason,
          banner: banner,
          onRefresh: controller.refresh,
        ),
      EnrolmentAwaitingCode(:final errorMessage) => CodeEntryScreen(
          key: const ValueKey('code'),
          errorMessage: errorMessage,
          banner: banner,
          onSubmit: controller.submitCode,
        ),
      EnrolmentRefused(:final reason) => OutcomeScreen(
          key: const ValueKey('refused'),
          title: EnrolmentCopy.refusedTitle,
          body: reason,
          banner: banner,
          onStartOver: controller.startOver,
        ),
      EnrolmentLocked() => OutcomeScreen(
          key: const ValueKey('locked'),
          title: EnrolmentCopy.refusedTitle,
          body: EnrolmentCopy.lockedBody,
          banner: banner,
          onStartOver: controller.startOver,
        ),
      EnrolmentExpired() => OutcomeScreen(
          key: const ValueKey('expired'),
          title: EnrolmentCopy.pendingTitle,
          body: copy.expiredBody,
          banner: banner,
          onStartOver: controller.startOver,
        ),
      // The app root replaces this flow with the home screen as soon as it sees Done.
      EnrolmentDone() || EnrolmentFailure() => const ScreenScaffold(
          title: EnrolmentCopy.loading,
          children: [LinearProgressIndicator()],
        ),
    };
  }
}
