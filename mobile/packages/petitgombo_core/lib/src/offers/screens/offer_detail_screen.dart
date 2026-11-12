import 'package:flutter/material.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/ui_kit.dart';
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
        const SizedBox(height: Gaps.md),
        Text(
          JobberCopy.comingSoon,
          style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
