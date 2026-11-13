import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../applications/application_copy.dart';
import '../../app/theme.dart';
import '../../verification/screens/checklist_screen.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
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
      OfferStatus.booked => Icons.event_available,
      OfferStatus.refused => Icons.error_outline,
      OfferStatus.withdrawn => Icons.remove_circle_outline,
      OfferStatus.closed => Icons.event_busy,
    };

/// The householder's own offers, with the means to create one.
class MyOffersScreen extends ConsumerStatefulWidget {
  const MyOffersScreen({super.key, this.onSignOut});

  /// Shown as a button at the bottom when set; the app shell offers it in the profile instead.
  final VoidCallback? onSignOut;

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
    final signOut = widget.onSignOut;
    _open(
      ChecklistScreen(
        onBack: () => Navigator.of(context).pop(),
        onSignOut: signOut == null
            ? null
            : () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                signOut();
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
        child: Align(
          alignment: Alignment.topCenter,
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
                    Text(OfferCopy.myOffersTitle, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.xs),
                    Text(
                      OfferCopy.myOffersSubtitle,
                      style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: Gaps.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Gaps.xl),
                        onTap: _openChecklist,
                        child: const StatusPill(
                          icon: Icons.verified_user,
                          label: OfferCopy.verifiedRow,
                          strong: true,
                        ),
                      ),
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
                        FilledButton.icon(
                          onPressed: () => _open(const OfferFormFlow()),
                          icon: const Icon(Icons.add),
                          label: const Text(OfferCopy.createOffer),
                        )
                      else
                        const PrivacyNote(OfferCopy.notVerifiedHint),
                      const SizedBox(height: Gaps.lg),
                      if (data.offers.isEmpty)
                        const EmptyState(
                          icon: Icons.assignment_outlined,
                          title: OfferCopy.emptyMine,
                          body: OfferCopy.emptyMineBody,
                        )
                      else
                        for (final offer in data.offers)
                          _OfferCard(
                            offer: offer,
                            title: offerTitle(offer, state.categories),
                            onTap: () => _open(MyOfferDetailScreen(offerId: offer.id)),
                          ),
                    ],
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: Gaps.xl),
                      OutlinedButton(
                        onPressed: widget.onSignOut,
                        child: const Text(OfferCopy.signOut),
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

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.title, required this.onTap});

  final MyOffer offer;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: categoryIcon(title)),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gaps.sm),
                MetaChip(
                  icon: Icons.event_outlined,
                  label: formatWhen(offer.startsAt, offer.durationMinutes),
                ),
                const SizedBox(height: Gaps.xs),
                MetaChip(icon: Icons.payments_outlined, label: formatXof(offer.payXof)),
                const SizedBox(height: Gaps.md),
                StatusPill(
                  icon: statusIcon(offer.status),
                  label: OfferCopy.statusLabel(offer.status),
                  strong: offer.status == OfferStatus.published,
                ),
                if (offer.applicantsCount > 0) ...[
                  const SizedBox(height: Gaps.sm),
                  MetaChip(
                    icon: Icons.people_outline,
                    label: ApplicationCopy.applicantCount(offer.applicantsCount),
                  ),
                ],
              ],
            ),
          ),
        ],
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
