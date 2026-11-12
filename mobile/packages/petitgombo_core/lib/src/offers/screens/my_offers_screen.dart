import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../verification/screens/checklist_screen.dart';
import '../../widgets/message_banner.dart';
import '../my_offers_controller.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';
import 'my_offer_detail_screen.dart';
import 'offer_form_flow.dart';

/// The offer's title: its category name, or the catalogue's name for a draft.
String offerTitle(MyOffer offer, List<OfferCategory> categories) {
  if (offer.categoryName.isNotEmpty) return offer.categoryName;
  for (final category in categories) {
    if (category.id == offer.categoryId) return category.name;
  }
  return OfferCopy.draftFallback;
}

IconData statusIcon(OfferStatus status) => switch (status) {
      OfferStatus.draft => Icons.edit_note,
      OfferStatus.inReview => Icons.schedule,
      OfferStatus.published => Icons.check_circle_outline,
      OfferStatus.refused => Icons.error_outline,
      OfferStatus.withdrawn => Icons.remove_circle_outline,
      OfferStatus.closed => Icons.event_busy,
    };

/// The householder's own offers, with the means to create one.
class MyOffersScreen extends ConsumerStatefulWidget {
  const MyOffersScreen({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  ConsumerState<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends ConsumerState<MyOffersScreen> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (mounted) await ref.read(myOffersControllerProvider.notifier).load();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)).then((_) {
      if (mounted) _load();
    });
  }

  void _openChecklist() {
    _open(
      ChecklistScreen(
        onBack: () => Navigator.of(context).pop(),
        onSignOut: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          widget.onSignOut();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(myOffersControllerProvider);
    final data = state.data;
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gaps.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: Gaps.lg),
                    Text(OfferCopy.myOffersTitle, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.sm),
                    TextButton.icon(
                      onPressed: _openChecklist,
                      icon: Icon(Icons.verified_user, color: theme.colorScheme.primary),
                      label: const Text(OfferCopy.verifiedRow),
                    ),
                    const SizedBox(height: Gaps.lg),
                    if (state.error != null && onTop) ...[
                      MessageBanner(
                        message: state.error!,
                        actionLabel: OfferCopy.retry,
                        onAction: _load,
                      ),
                      const SizedBox(height: Gaps.lg),
                    ],
                    if (data == null)
                      for (var i = 0; i < 3; i++) const _SkeletonCard()
                    else ...[
                      if (data.canPublish)
                        FilledButton(
                          onPressed: () => _open(const OfferFormFlow()),
                          child: const Text(OfferCopy.createOffer),
                        )
                      else
                        Text(OfferCopy.notVerifiedHint, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: Gaps.lg),
                      if (data.offers.isEmpty)
                        Text(OfferCopy.emptyMine, style: theme.textTheme.bodyLarge)
                      else
                        for (final offer in data.offers)
                          _OfferCard(
                            offer: offer,
                            title: offerTitle(offer, state.categories),
                            onTap: () => _open(MyOfferDetailScreen(offerId: offer.id)),
                          ),
                    ],
                    const SizedBox(height: Gaps.xl),
                    OutlinedButton(
                      onPressed: widget.onSignOut,
                      child: const Text(OfferCopy.signOut),
                    ),
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

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.title, required this.onTap});

  final MyOffer offer;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gaps.xs),
                Text(formatWhen(offer.startsAt, offer.durationMinutes),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: Gaps.xs),
                Text(formatXof(offer.payXof), style: theme.textTheme.bodyMedium),
                const SizedBox(height: Gaps.sm),
                Row(
                  children: [
                    Icon(statusIcon(offer.status), size: Gaps.lg, color: AppColors.textMuted),
                    const SizedBox(width: Gaps.xs),
                    Expanded(
                      child: Text(
                        OfferCopy.statusLabel(offer.status),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grey block shaped like an offer card, shown while the list loads.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      margin: const EdgeInsets.only(bottom: Gaps.md),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
