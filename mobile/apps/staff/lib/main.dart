import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'src/providers.dart';
import 'src/screens/device_pending_screen.dart';
import 'src/screens/enrolment_detail_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/queue_screen.dart';
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

    // A dialog left open must not survive a sign-out or a return to the queue.
    ref.listen(staffControllerProvider.select((s) => (s.stage, s.selected?.id)), (_, __) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    });

    switch (state.stage) {
      case StaffStage.login:
        return LoginScreen(onSubmit: controller.signIn, busy: state.busy, error: state.error);
      case StaffStage.devicePending:
        return DevicePendingScreen(onRetry: controller.signOut);
      case StaffStage.queue:
        final selected = state.selected;
        if (selected == null) {
          return QueueScreen(
            state: state,
            onTab: controller.selectTab,
            onRefresh: controller.refresh,
            onOpen: controller.open,
            onSignOut: controller.signOut,
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
