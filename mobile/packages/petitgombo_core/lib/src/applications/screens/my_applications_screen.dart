import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../offers/offer_copy.dart';
import '../../offers/offer_format.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../application_models.dart';
import '../applications_controller.dart';
import 'jobber_booking_screen.dart';

/// The offers the jobber applied to, and what became of each.
class MyApplicationsScreen extends ConsumerStatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  ConsumerState<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends ConsumerState<MyApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(applicationsControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(applicationsControllerProvider);
    final rows = state.applications;
    final jobs = (state.bookings ?? const <JobberBooking>[])
        .where((b) => b.status != 'cancelled' && b.status != 'expired')
        .toList();
    return FlowScaffold(
      title: ApplicationCopy.myApplications,
      banner: state.error == null
          ? null
          : MessageBanner(
              message: state.error!,
              actionLabel: OfferCopy.retry,
              onAction: ref.read(applicationsControllerProvider.notifier).load,
            ),
      children: [
        if (rows == null && state.error == null)
          for (var i = 0; i < 3; i++) const _Skeleton()
        else if (rows != null && rows.isEmpty)
          const EmptyState(
            icon: Icons.send_outlined,
            title: ApplicationCopy.noApplications,
            body: ApplicationCopy.noApplicationsBody,
          )
        else if (rows != null)
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.offer.categoryName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Gaps.sm),
                    MetaChip(
                      icon: Icons.event_outlined,
                      label: formatWhen(row.offer.startsAt, row.offer.durationMinutes),
                    ),
                    const SizedBox(height: Gaps.xs),
                    MetaChip(
                      icon: Icons.place_outlined,
                      label: '${row.offer.commune} · ${row.offer.quartier}',
                    ),
                    const SizedBox(height: Gaps.md),
                    StatusPill(
                      icon: _icon(row.status),
                      label: ApplicationCopy.applicationStatus(
                        row.status,
                        offerGone: row.offer.status != 'published',
                      ),
                      strong: row.status == ApplicationStatus.accepted,
                    ),
                    if (row.status == ApplicationStatus.accepted) ...[
                      const SizedBox(height: Gaps.sm),
                      Text(ApplicationCopy.acceptedWaiting, style: theme.textTheme.bodyMedium),
                    ],
                    if (row.status == ApplicationStatus.pending) ...[
                      const SizedBox(height: Gaps.sm),
                      TextButton(
                        onPressed: state.sending
                            ? null
                            : () =>
                                ref.read(applicationsControllerProvider.notifier).withdraw(row.id),
                        child: const Text(ApplicationCopy.withdraw),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        if (jobs.isNotEmpty) ...[
          const SizedBox(height: Gaps.lg),
          const SectionHeader(ApplicationCopy.myJobs),
          for (final job in jobs)
            AppCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => JobberBookingScreen(booking: job)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.categoryName, style: theme.textTheme.titleMedium),
                        const SizedBox(height: Gaps.xs),
                        Text(
                          ApplicationCopy.jobStatus(job, DateTime.now()),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
        ],
      ],
    );
  }

  IconData _icon(ApplicationStatus status) => switch (status) {
        ApplicationStatus.pending => Icons.schedule,
        ApplicationStatus.accepted => Icons.check_circle_outline,
        ApplicationStatus.declined => Icons.remove_circle_outline,
        ApplicationStatus.withdrawn => Icons.undo,
      };
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      margin: const EdgeInsets.only(bottom: Gaps.sm),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
