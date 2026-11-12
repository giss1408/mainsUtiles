import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../api/models.dart';
import '../enrolment/enrolment_controller.dart';
import '../enrolment/enrolment_copy.dart';
import '../enrolment/enrolment_flow.dart';
import '../enrolment/enrolment_state.dart';
import '../home/home_placeholder_screen.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_scaffold.dart';
import 'app_role.dart';
import 'device_description.dart';
import 'providers.dart';
import 'theme.dart';

class PetitGomboApp extends StatelessWidget {
  const PetitGomboApp({
    super.key,
    required this.role,
    this.device = const DeviceDescription.unknown(),
    this.overrides = const [],
  });

  final AppRole role;
  final DeviceDescription device;
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appRoleProvider.overrideWithValue(role),
        deviceDescriptionProvider.overrideWithValue(device),
        ...overrides,
      ],
      child: MaterialApp(
        title: role == AppRole.jobber ? 'petitGombo Jobber' : 'petitGombo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _AppRoot(),
      ),
    );
  }
}

enum _Stage { starting, offline, enrolment, signedIn, signedOut }

/// Decides between the enrolment flow and the signed-in home.
class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> with WidgetsBindingObserver {
  _Stage _stage = _Stage.starting;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the moment to ask whether staff have answered.
    if (state != AppLifecycleState.resumed || _stage != _Stage.enrolment) return;
    final enrolment = ref.read(enrolmentControllerProvider);
    if (enrolment is EnrolmentPending || enrolment is EnrolmentHeld) {
      ref.read(enrolmentControllerProvider.notifier).refresh();
    }
  }

  Future<void> _start() async {
    setState(() => _stage = _Stage.starting);
    try {
      final me = await ref.read(sessionProvider).restore();
      if (me == null) {
        await ref.read(enrolmentControllerProvider.notifier).resume();
      }
      if (!mounted) return;
      setState(() => _stage = me == null ? _Stage.enrolment : _Stage.signedIn);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.offline;
        _error = e.isNetwork ? offlineMessage : genericErrorMessage;
      });
    }
  }

  Future<void> _signOut() async {
    await ref.read(sessionProvider).signOut();
    if (mounted) setState(() => _stage = _Stage.signedOut);
  }

  Future<void> _signIn() async {
    try {
      final Me _ = await ref.read(sessionProvider).signIn();
      if (mounted) setState(() => _stage = _Stage.signedIn);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        setState(() => _error = offlineMessage);
      } else {
        // The device is no longer accepted: it has to be enrolled again.
        await ref.read(enrolmentControllerProvider.notifier).startOver();
        if (mounted) setState(() => _stage = _Stage.enrolment);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = EnrolmentCopy.forRole(ref.watch(appRoleProvider));

    ref.listen(enrolmentControllerProvider, (previous, next) {
      if (next is EnrolmentDone && _stage == _Stage.enrolment) {
        setState(() => _stage = _Stage.signedIn);
      }
    });

    return switch (_stage) {
      _Stage.starting => const ScreenScaffold(
          title: 'petitGombo',
          children: [LinearProgressIndicator(), SizedBox(height: 12), Text(EnrolmentCopy.loading)],
        ),
      _Stage.offline => ScreenScaffold(
          title: 'petitGombo',
          icon: Icons.wifi_off,
          children: [
            Text(_error ?? offlineMessage, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: _start, child: const Text(EnrolmentCopy.retryLabel)),
          ],
        ),
      _Stage.enrolment => const EnrolmentFlow(),
      _Stage.signedIn => HomePlaceholderScreen(roleLabel: copy.roleLabel, onSignOut: _signOut),
      _Stage.signedOut => ScreenScaffold(
          title: 'petitGombo',
          icon: Icons.lock_outline,
          banner: _error == null ? null : MessageBanner(message: _error!),
          children: [
            Text(EnrolmentCopy.signedOutBody, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: _signIn, child: const Text(EnrolmentCopy.signInLabel)),
          ],
        ),
    };
  }
}
