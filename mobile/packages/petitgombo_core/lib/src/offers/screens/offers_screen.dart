import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../applications/application_copy.dart';
import '../../applications/screens/my_applications_screen.dart';
import '../../widgets/message_banner.dart';
import '../../verification/screens/verification_card.dart';
import '../../verification/verification_controller.dart';
import '../../widgets/ui_kit.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';
import '../offers_controller.dart';
import 'offer_detail_screen.dart';

/// The published offers, for a jobber, with a commune filter.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key, this.onSignOut});

  /// Shown as a button at the bottom when set; the app shell offers it in the profile instead.
  final VoidCallback? onSignOut;

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_firstLoad);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    if (mounted) await ref.read(offersControllerProvider.notifier).load();
  }

  /// Offers come first; the verification card is a bonus and never delays them.
  Future<void> _firstLoad() async {
    await _reload();
    if (mounted) await ref.read(verificationControllerProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(offersControllerProvider);
    final controller = ref.read(offersControllerProvider.notifier);
    final offers = state.offers;
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gaps.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(JobberCopy.title, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.xs),
                    Text(
                      JobberCopy.subtitle,
                      style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: Gaps.lg),
                    const VerificationCard(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gaps.lg),
                      child: AppCard(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const MyApplicationsScreen()),
                        ),
                        child: Row(
                          children: [
                            const IconTile(icon: Icons.send_outlined),
                            const SizedBox(width: Gaps.md),
                            Expanded(
                              child: Text(
                                ApplicationCopy.myApplications,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textMuted),
                          ],
                        ),
                      ),
                    ),
                    DropdownButtonFormField<String?>(
                      value: state.commune,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: JobberCopy.communeLabel),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text(JobberCopy.allCommunes),
                        ),
                        for (final commune in state.communes)
                          DropdownMenuItem<String?>(value: commune, child: Text(commune)),
                      ],
                      onChanged: (commune) => controller.setCommune(commune),
                    ),
                    const SizedBox(height: Gaps.lg),
                    if (state.error != null && onTop) ...[
                      MessageBanner(
                        message: state.error!,
                        actionLabel: JobberCopy.retry,
                        onAction: _reload,
                      ),
                      const SizedBox(height: Gaps.lg),
                    ],
                    if (offers == null)
                      for (var i = 0; i < 3; i++) const _SkeletonCard()
                    else if (offers.isEmpty)
                      EmptyState(
                        icon: Icons.search_off,
                        title: state.commune == null ? JobberCopy.empty : JobberCopy.emptyInCommune,
                        body: JobberCopy.emptyBody,
                      )
                    else
                      for (final offer in offers)
                        _OfferCard(
                          offer: offer,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => OfferDetailScreen(offer: offer)),
                          ),
                        ),
                    if (state.hasMore) ...[
                      const SizedBox(height: Gaps.sm),
                      OutlinedButton(
                        onPressed: state.loading ? null : controller.loadMore,
                        child: const Text(JobberCopy.seeMore),
                      ),
                    ],
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: Gaps.xl),
                      OutlinedButton(
                        onPressed: widget.onSignOut,
                        child: const Text(JobberCopy.signOut),
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
  const _OfferCard({required this.offer, required this.onTap});

  final PublicOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: categoryIcon(offer.categoryName)),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.categoryName, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gaps.xs),
                Text(
                  formatXof(offer.payXof),
                  style: theme.textTheme.titleMedium!.copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: Gaps.sm),
                MetaChip(
                  icon: Icons.event_outlined,
                  label: formatWhen(offer.startsAt, offer.durationMinutes),
                ),
                const SizedBox(height: Gaps.xs),
                MetaChip(
                  icon: Icons.place_outlined,
                  label: '${offer.commune} · ${offer.quartier}',
                ),
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
      height: 128,
      margin: const EdgeInsets.only(bottom: Gaps.md),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
