import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../applications/application_copy.dart';
import '../../applications/screens/applicants_screen.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../my_offers_controller.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';
import 'my_offers_screen.dart';
import 'offer_form_flow.dart';

/// One of the householder's offers, with the actions its status allows.
class MyOfferDetailScreen extends ConsumerWidget {
  const MyOfferDetailScreen({super.key, required this.offerId});

  final String offerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myOffersControllerProvider);
    final offer = _find(state);
    if (offer == null) {
      return FlowScaffold(
        title: OfferCopy.offerNotFound,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(OfferCopy.backToOffers),
          ),
        ],
      );
    }
    return FlowScaffold(
      title: offerTitle(offer, state.categories),
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            icon: statusIcon(offer.status),
            label: OfferCopy.statusLabel(offer.status),
            strong: offer.status == OfferStatus.published,
          ),
        ),
        const SizedBox(height: Gaps.lg),
        if (offer.booking != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: AppCard(
              child: Row(
                children: [
                  const IconTile(icon: Icons.event_available),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Text(
                      ApplicationCopy.bookingLine(offer.booking!.jobberFirstName),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (offer.status == OfferStatus.published)
          Padding(
            padding: const EdgeInsets.only(bottom: Gaps.sm),
            child: AppCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ApplicantsScreen(offerId: offer.id)),
              ),
              child: Row(
                children: [
                  const IconTile(icon: Icons.people_outline),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Text(
                      offer.applicantsCount == 0
                          ? ApplicationCopy.noApplicants
                          : ApplicationCopy.applicantCount(offer.applicantsCount),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        if (offer.reason.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(OfferCopy.reasonLabel, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: Gaps.xs),
                Text(offer.reason, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetaChip(
                icon: Icons.event_outlined,
                label: formatWhen(offer.startsAt, offer.durationMinutes),
              ),
              const SizedBox(height: Gaps.sm),
              MetaChip(icon: Icons.payments_outlined, label: formatXof(offer.payXof)),
              if (offer.commune.isNotEmpty) ...[
                const SizedBox(height: Gaps.sm),
                MetaChip(icon: Icons.place_outlined, label: '${offer.commune}, ${offer.quartier}'),
              ],
              const SizedBox(height: Gaps.lg),
              for (final duty in offer.duties)
                Text('• $duty', style: Theme.of(context).textTheme.bodyLarge),
              if (offer.note.isNotEmpty) ...[
                const SizedBox(height: Gaps.md),
                Text(offer.note, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gaps.xl),
        ..._actions(context, ref, offer),
      ],
    );
  }

  MyOffer? _find(MyOffersState state) {
    for (final offer in state.data?.offers ?? const <MyOffer>[]) {
      if (offer.id == offerId) return offer;
    }
    return null;
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, MyOffer offer) {
    final controller = ref.read(myOffersControllerProvider.notifier);
    if (offer.status == OfferStatus.draft) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => OfferFormFlow(draft: offer)),
          ),
          child: const Text(OfferCopy.editAction),
        ),
        const SizedBox(height: Gaps.sm),
        OutlinedButton(
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              title: OfferCopy.deleteTitle,
              action: OfferCopy.deleteAction,
            );
            if (!confirmed || !context.mounted) return;
            if (await controller.delete(offer.id) && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text(OfferCopy.deleteAction),
        ),
      ];
    }
    if (offer.status == OfferStatus.inReview ||
        offer.status == OfferStatus.published ||
        offer.status == OfferStatus.booked) {
      return [
        OutlinedButton(
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              title: OfferCopy.withdrawTitle,
              action: 'Retirer',
              body: offer.status == OfferStatus.booked
                  ? OfferCopy.withdrawBookedBody
                  : OfferCopy.withdrawBody,
            );
            if (confirmed) await controller.withdraw(offer.id);
          },
          child: const Text(OfferCopy.withdrawAction),
        ),
      ];
    }
    if (offer.status.canCopy) {
      return [
        FilledButton(
          onPressed: () async {
            final copy = await controller.copy(offer.id);
            if (copy != null && context.mounted) {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => OfferFormFlow(draft: copy)),
              );
            }
          },
          child: const Text(OfferCopy.copyAction),
        ),
      ];
    }
    return const [];
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String action,
    String? body,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(OfferCopy.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }
}
