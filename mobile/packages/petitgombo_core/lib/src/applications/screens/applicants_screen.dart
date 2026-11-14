import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../offers/offer_copy.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../application_models.dart';
import '../applicants_controller.dart';

/// The people who applied to one offer. The householder accepts one of them.
class ApplicantsScreen extends ConsumerStatefulWidget {
  const ApplicantsScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends ConsumerState<ApplicantsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(applicantsControllerProvider(widget.offerId).notifier).load());
  }

  Future<void> _accept(ApplicantCard applicant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ApplicationCopy.acceptTitle(applicant.firstName)),
        content: const Text(ApplicationCopy.acceptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(OfferCopy.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(ApplicationCopy.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final booking =
        await ref.read(applicantsControllerProvider(widget.offerId).notifier).accept(applicant.id);
    if (booking != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(applicantsControllerProvider(widget.offerId));
    final rows = state.applicants;
    return FlowScaffold(
      title: ApplicationCopy.applicantsTitle,
      banner: state.error == null
          ? null
          : MessageBanner(
              message: state.error!,
              actionLabel: OfferCopy.retry,
              onAction: ref.read(applicantsControllerProvider(widget.offerId).notifier).load,
            ),
      children: [
        if (!state.paymentAvailable) ...[
          const MessageBanner(message: ApplicationCopy.unavailable),
          const SizedBox(height: Gaps.lg),
        ],
        if (rows == null && state.error == null)
          const Center(child: CircularProgressIndicator())
        else if (rows != null && rows.isEmpty)
          const EmptyState(
            icon: Icons.people_outline,
            title: ApplicationCopy.noApplicants,
            body: ApplicationCopy.noApplicantsBody,
          )
        else if (rows != null)
          for (final applicant in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(applicant.firstName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Gaps.sm),
                    Wrap(
                      spacing: Gaps.sm,
                      runSpacing: Gaps.xs,
                      children: [
                        const StatusPill(
                          icon: Icons.verified_user_outlined,
                          label: ApplicationCopy.jobberLabel,
                          strong: true,
                        ),
                        MetaChip(
                          icon: Icons.work_outline,
                          label: ApplicationCopy.jobsDone(applicant.jobsDone),
                        ),
                        if (applicant.rating != null)
                          MetaChip(
                            icon: Icons.star_outline,
                            label: ApplicationCopy.ratingLabel(applicant.rating!),
                          ),
                      ],
                    ),
                    if (applicant.message.isNotEmpty) ...[
                      const SizedBox(height: Gaps.md),
                      Text(applicant.message, style: theme.textTheme.bodyLarge),
                    ],
                    const SizedBox(height: Gaps.md),
                    if (state.paymentAvailable)
                      FilledButton(
                        onPressed: state.sending ? null : () => _accept(applicant),
                        child: const Text(ApplicationCopy.accept),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
