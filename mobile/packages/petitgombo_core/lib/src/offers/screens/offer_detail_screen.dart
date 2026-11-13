import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error.dart';
import '../../app/providers.dart';
import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../applications/application_copy.dart';
import '../../applications/application_models.dart';
import '../../applications/applications_controller.dart';
import '../../applications/screens/apply_screen.dart';
import '../../verification/screens/checklist_screen.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../verification/verification_controller.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';
import '../offers_api.dart';

/// One published offer. A jobber can apply to it; the exact address is never shown.
class OfferDetailScreen extends ConsumerStatefulWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final PublicOffer offer;

  @override
  ConsumerState<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends ConsumerState<OfferDetailScreen> {
  late PublicOffer _offer = widget.offer;

  @override
  void initState() {
    super.initState();
    // The list carries no trust line and no application: the detail does.
    Future.microtask(() async {
      await _loadDetail();
      if (mounted && ref.read(verificationControllerProvider).checklist == null) {
        await ref.read(verificationControllerProvider.notifier).load();
      }
    });
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await ref.read(sessionProvider).authorized(
            (access) => ref.read(offersApiProvider).offer(access, widget.offer.id),
          );
      if (mounted) setState(() => _offer = detail);
    } on ApiError {
      // The list data is still shown; applying will report what is wrong.
    }
  }

  Future<void> _apply() async {
    final receipt = await Navigator.of(context).push<ApplicationReceipt>(
      MaterialPageRoute(builder: (_) => ApplyScreen(offer: _offer)),
    );
    if (receipt != null && mounted) {
      setState(() => _offer = _offer.withMyApplication(
            MyApplicationRef(id: receipt.id, status: receipt.status),
          ));
    }
  }

  Future<void> _withdraw(String id) async {
    final done = await ref.read(applicationsControllerProvider.notifier).withdraw(id);
    if (done && mounted) setState(() => _offer = _offer.withMyApplication(null));
  }

  Widget _action(BuildContext context) {
    final theme = Theme.of(context);
    final mine = _offer.myApplication;
    final checklist = ref.watch(verificationControllerProvider).checklist;
    final busy = ref.watch(applicationsControllerProvider).sending;
    if (mine != null && mine.status == ApplicationStatus.pending) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusPill(icon: Icons.schedule, label: ApplicationCopy.sent),
            const SizedBox(height: Gaps.sm),
            Text(ApplicationCopy.sentBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Gaps.md),
            OutlinedButton(
              onPressed: busy ? null : () => _withdraw(mine.id),
              child: const Text(ApplicationCopy.withdraw),
            ),
          ],
        ),
      );
    }
    if (mine != null) {
      return StatusPill(
        icon: Icons.check_circle_outline,
        label: ApplicationCopy.applicationStatus(mine.status),
        strong: mine.status == ApplicationStatus.accepted,
      );
    }
    if (checklist != null && !checklist.verified) {
      return FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChecklistScreen(onBack: () => Navigator.of(context).pop()),
          ),
        ),
        child: const Text(ApplicationCopy.finishVerification),
      );
    }
    return FilledButton(onPressed: _apply, child: const Text(ApplicationCopy.apply));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offer = _offer;
    final error = ref.watch(applicationsControllerProvider).error;
    final trust = offer.householder;
    return FlowScaffold(
      banner: error == null ? null : MessageBanner(message: error),
      title: offer.categoryName,
      children: [
        if (trust != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: MetaChip(
                icon: Icons.verified_user_outlined, label: ApplicationCopy.trustLine(trust)),
          ),
        AppCard(
          child: Row(
            children: [
              IconTile(icon: categoryIcon(offer.categoryName), size: 56),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(JobberCopy.payLabel, style: theme.textTheme.bodySmall),
                    Text(
                      formatXof(offer.payXof),
                      style: theme.textTheme.headlineMedium!.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(JobberCopy.whenLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gaps.sm),
              MetaChip(
                icon: Icons.event_outlined,
                label: formatWhen(offer.startsAt, offer.durationMinutes),
              ),
              const SizedBox(height: Gaps.xs),
              MetaChip(
                icon: Icons.timelapse,
                label: '${JobberCopy.durationLabel} : ${formatDuration(offer.durationMinutes)}',
              ),
              const SizedBox(height: Gaps.lg),
              Text(JobberCopy.placeLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gaps.sm),
              MetaChip(icon: Icons.place_outlined, label: '${offer.commune} · ${offer.quartier}'),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(JobberCopy.tasks, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gaps.sm),
              for (final duty in offer.duties) Text('• $duty', style: theme.textTheme.bodyLarge),
              if (offer.note.isNotEmpty) ...[
                const SizedBox(height: Gaps.lg),
                Text(JobberCopy.noteLabel, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gaps.sm),
                Text(offer.note, style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
        const PrivacyNote(JobberCopy.addressNotice),
        const SizedBox(height: Gaps.lg),
        _action(context),
      ],
    );
  }
}
