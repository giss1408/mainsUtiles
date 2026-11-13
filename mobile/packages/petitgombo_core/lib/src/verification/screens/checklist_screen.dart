import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../widgets/message_banner.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import '../verification_models.dart';
import 'address_flow.dart';
import 'flow_scaffold.dart';
import 'guarantor_flow.dart';
import 'home_location_screen.dart';
import 'identity_flow.dart';

/// The householder's home screen until verified: three steps, each with its status.
class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key, this.onSignOut, this.onBack});

  /// Shown as a button at the bottom when set.
  final VoidCallback? onSignOut;

  /// Set when the checklist is opened from another screen: shows a back arrow.
  final VoidCallback? onBack;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the moment to ask whether staff have decided.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (mounted) await ref.read(verificationControllerProvider.notifier).load();
  }

  void _open(Widget flow) {
    ref.read(verificationControllerProvider.notifier).clearError();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => flow));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(verificationControllerProvider);
    final voice = ref.watch(verificationVoiceProvider);
    final checklist = state.checklist;
    // An error raised inside a step belongs to that step's screen, not to this one.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;

    return Scaffold(
      appBar: widget.onBack == null ? null : AppBar(leading: BackButton(onPressed: widget.onBack)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: flowMaxWidth),
            child: RefreshIndicator(
              onRefresh: _load,
              // Not a lazy list: every step stays reachable for screen readers and tests.
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gaps.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Gaps.xl),
                    Text(voice.title, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.sm),
                    if (checklist != null && checklist.verified)
                      _VerifiedNote(body: voice.verifiedBody)
                    else
                      Text(voice.intro, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: Gaps.lg),
                    if (state.error != null && onTop) ...[
                      MessageBanner(
                        message: state.error!,
                        actionLabel: VerificationCopy.retry,
                        onAction: _load,
                      ),
                      const SizedBox(height: Gaps.lg),
                    ],
                    if (checklist == null)
                      for (var i = 0; i < 3; i++) const _SkeletonCard()
                    else if (checklist.forJobber) ...[
                      _StepCard(
                        title: VerificationCopy.identityTitle,
                        step: checklist.identity,
                        reviewHours: checklist.reviewHours,
                        onStart: () => _open(const IdentityFlow()),
                      ),
                      _StepCard(
                        title: VerificationCopy.guarantorTitle,
                        step: checklist.guarantor,
                        reviewHours: checklist.reviewHours,
                        onStart: () => _open(const GuarantorFlow()),
                      ),
                    ] else ...[
                      _StepCard(
                        title: VerificationCopy.identityTitle,
                        step: checklist.identity,
                        reviewHours: checklist.reviewHours,
                        onStart: () => _open(const IdentityFlow()),
                      ),
                      _StepCard(
                        title: VerificationCopy.addressTitle,
                        step: checklist.address,
                        reviewHours: checklist.reviewHours,
                        onStart: () => _open(const AddressFlow()),
                      ),
                      _StepCard(
                        title: VerificationCopy.homeTitle,
                        step: checklist.homeLocation,
                        reviewHours: checklist.reviewHours,
                        onStart: () => _open(const HomeLocationScreen()),
                      ),
                    ],
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: Gaps.xl),
                      OutlinedButton(
                        onPressed: widget.onSignOut,
                        child: const Text(VerificationCopy.signOut),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifiedNote extends StatelessWidget {
  const _VerifiedNote({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user, color: theme.colorScheme.primary),
        const SizedBox(width: Gaps.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(VerificationCopy.verified, style: theme.textTheme.titleMedium),
              Text(body, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.step,
    required this.reviewHours,
    required this.onStart,
  });

  final String title;
  final VerificationStep step;
  final int reviewHours;
  final VoidCallback onStart;

  (IconData, Color) _icon(BuildContext context) => switch (step.status) {
        StepStatus.notStarted => (Icons.radio_button_unchecked, AppColors.textMuted),
        StepStatus.submitted || StepStatus.inReview => (Icons.schedule, AppColors.textMuted),
        StepStatus.confirmed => (Icons.check_circle, Theme.of(context).colorScheme.primary),
        StepStatus.refused || StepStatus.expired => (Icons.error_outline, AppColors.warning),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _icon(context);
    final status = VerificationCopy.statusText(step, reviewHours);
    return Container(
      margin: const EdgeInsets.only(bottom: Gaps.md),
      padding: const EdgeInsets.all(Gaps.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: Gaps.xs),
                      Text(status, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (step.status.canStart) ...[
            const SizedBox(height: Gaps.md),
            if (step.status == StepStatus.notStarted)
              FilledButton(onPressed: onStart, child: const Text(VerificationCopy.start))
            else
              OutlinedButton(onPressed: onStart, child: const Text(VerificationCopy.restart)),
          ],
        ],
      ),
    );
  }
}

/// A grey block shaped like a step card, shown while the checklist loads.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      margin: const EdgeInsets.only(bottom: Gaps.md),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
