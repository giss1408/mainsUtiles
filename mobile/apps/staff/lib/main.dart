import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'src/ops_controller.dart';
import 'src/providers.dart';
import 'src/screens/contact_detail_screen.dart';
import 'src/screens/contacts_queue_screen.dart';
import 'src/screens/device_pending_screen.dart';
import 'src/screens/enrolment_detail_screen.dart';
import 'src/screens/jobs_screens.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/messages_screens.dart';
import 'src/screens/payment_detail_screen.dart';
import 'src/screens/payments_queue_screen.dart';
import 'src/screens/queue_screen.dart';
import 'src/screens/section_bar.dart';
import 'src/staff_controller.dart';
import 'src/staff_copy.dart';

/// The staff app: sign-in on an activated phone, then the enrolment queue.
Widget buildApp({
  DeviceDescription device = const DeviceDescription.unknown(),
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: [deviceDescriptionProvider.overrideWithValue(device), ...overrides],
      child: MaterialApp(
        title: StaffCopy.appName,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _Root(),
      ),
    );

/// Picks the screen from the controller's state.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(staffControllerProvider);
    final controller = ref.read(staffControllerProvider.notifier);

    final ops = ref.watch(opsControllerProvider);
    final opsController = ref.read(opsControllerProvider.notifier);

    // A dialog left open must not survive a sign-out or a return to the queue.
    ref.listen(
        staffControllerProvider.select(
          (s) => (s.stage, s.selected?.id, s.contactSelected?.id, s.paymentSelected?.id),
        ), (_, __) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
    ref.listen(
        opsControllerProvider.select(
          (s) => (s.messageSelected?.id, s.payoutSelected?.id, s.disputeSelected?.id),
        ), (_, __) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
    // The operations follow the section: entering one loads its queue and the counts; signing
    // out drops everything they held.
    ref.listen(
      staffControllerProvider.select((s) => (s.stage, s.section)),
      (_, next) {
        if (next.$1 == StaffStage.queue) {
          opsController.enter(next.$2);
        } else {
          opsController.reset();
        }
      },
    );

    return AlertsScope(
      alerts: ops.alerts,
      child: _screen(context, ref, state, controller, ops, opsController),
    );
  }

  Widget _screen(
    BuildContext context,
    WidgetRef ref,
    StaffState state,
    StaffController controller,
    OpsState ops,
    OpsController opsController,
  ) {
    switch (state.stage) {
      case StaffStage.login:
        return LoginScreen(onSubmit: controller.signIn, busy: state.busy, error: state.error);
      case StaffStage.devicePending:
        return DevicePendingScreen(onRetry: controller.signOut);
      case StaffStage.queue:
        if (state.section == StaffSection.messages) {
          final message = ops.messageSelected;
          if (message == null) {
            return MessagesQueueScreen(
              state: ops,
              me: state.me,
              onRefresh: () async {
                await opsController.refreshMessages();
                await opsController.refreshAlerts();
              },
              onOpen: opsController.openMessage,
              onSignOut: controller.signOut,
              onSection: controller.selectSection,
            );
          }
          return MessageDetailScreen(
            // A new message is a new screen: nothing typed or tapped carries over.
            key: ValueKey(message.id),
            item: message,
            sendable: ops.messages?.any((m) => m.id == message.id) ?? false,
            busy: ops.busy,
            error: ops.error,
            opener: ref.watch(urlOpenerProvider),
            onBack: opsController.closeMessage,
            onSend: opsController.sendMessage,
          );
        }
        if (state.section == StaffSection.jobs) {
          final payout = ops.payoutSelected;
          if (payout != null) {
            return PayoutDetailScreen(
              key: ValueKey(payout.id),
              item: payout,
              busy: ops.busy,
              error: ops.error,
              onBack: opsController.closePayout,
              onPay: opsController.payPayout,
            );
          }
          final dispute = ops.disputeSelected;
          if (dispute != null) {
            return DisputeDetailScreen(
              key: ValueKey(dispute.id),
              item: dispute,
              busy: ops.busy,
              error: ops.error,
              onBack: opsController.closeDispute,
              onResolve: opsController.resolveDispute,
            );
          }
          return JobsQueueScreen(
            state: ops,
            me: state.me,
            onTab: opsController.selectJobsTab,
            onRefresh: opsController.refreshJobs,
            onOpenPayout: opsController.openPayout,
            onOpenDispute: opsController.openDispute,
            onSignOut: controller.signOut,
            onSection: controller.selectSection,
          );
        }
        if (state.section == StaffSection.payments) {
          final payment = state.paymentSelected;
          if (payment == null) {
            return PaymentsQueueScreen(
              state: state,
              onTab: controller.selectPaymentTab,
              onRefresh: controller.refreshPayments,
              onOpen: controller.openPayment,
              onSignOut: controller.signOut,
              onSection: controller.selectSection,
            );
          }
          return PaymentDetailScreen(
            item: payment,
            me: state.me!,
            proof: state.proof,
            busy: state.busy,
            error: state.error,
            onBack: controller.closePayment,
            onConfirm: controller.confirmPayment,
            onRefuse: controller.refusePayment,
            onRefund: controller.refundPayment,
          );
        }
        if (state.section == StaffSection.contacts) {
          final contact = state.contactSelected;
          if (contact == null) {
            return ContactsQueueScreen(
              state: state,
              onTab: controller.selectContactTab,
              onRefresh: controller.refreshContacts,
              onOpen: controller.openContact,
              onSignOut: controller.signOut,
              onSection: controller.selectSection,
            );
          }
          return ContactDetailScreen(
            item: contact,
            busy: state.busy,
            error: state.error,
            opener: ref.watch(urlOpenerProvider),
            onBack: controller.closeContact,
            onSend: controller.sendContact,
            onNotice: controller.noticeContact,
          );
        }
        final selected = state.selected;
        if (selected == null) {
          return QueueScreen(
            state: state,
            onTab: controller.selectTab,
            onRefresh: controller.refresh,
            onOpen: controller.open,
            onSignOut: controller.signOut,
            onSection: controller.selectSection,
          );
        }
        return EnrolmentDetailScreen(
          item: selected,
          me: state.me!,
          busy: state.busy,
          error: state.error,
          opener: ref.watch(urlOpenerProvider),
          onBack: controller.close,
          onApprove: controller.approve,
          onRefuse: controller.refuse,
          onHold: controller.hold,
          onSend: controller.send,
        );
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp(device: await DeviceDescription.detect()));
}
