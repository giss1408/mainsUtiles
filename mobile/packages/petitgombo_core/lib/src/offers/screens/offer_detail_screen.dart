import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';

/// One published offer. A jobber cannot apply yet, and the exact address is never shown.
class OfferDetailScreen extends StatelessWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final PublicOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FlowScaffold(
      title: offer.categoryName,
      children: [
        _Section(label: JobberCopy.tasks, children: [
          for (final duty in offer.duties) Text('• $duty', style: theme.textTheme.bodyLarge),
        ]),
        _Section(label: JobberCopy.whenLabel, children: [
          Text(formatWhen(offer.startsAt, offer.durationMinutes), style: theme.textTheme.bodyLarge),
        ]),
        _Section(label: JobberCopy.payLabel, children: [
          Text(formatXof(offer.payXof), style: theme.textTheme.bodyLarge),
        ]),
        _Section(label: JobberCopy.placeLabel, children: [
          Text('${offer.commune} · ${offer.quartier}', style: theme.textTheme.bodyLarge),
        ]),
        if (offer.note.isNotEmpty)
          _Section(label: JobberCopy.noteLabel, children: [
            Text(offer.note, style: theme.textTheme.bodyLarge),
          ]),
        Container(
          padding: const EdgeInsets.all(Gaps.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.textMuted),
              const SizedBox(width: Gaps.sm),
              Expanded(child: Text(JobberCopy.addressNotice, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
        const SizedBox(height: Gaps.md),
        Text(JobberCopy.comingSoon, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gaps.xs),
          ...children,
        ],
      ),
    );
  }
}
