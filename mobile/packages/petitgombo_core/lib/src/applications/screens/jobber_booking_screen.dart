import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../offers/offer_format.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../application_models.dart';
import '../applications_controller.dart';
import '../job_target.dart';
import 'report_screen.dart';
import 'review_screen.dart';

/// One job of the jobber: where and when, and once the window opens, the exact pin.
class JobberBookingScreen extends ConsumerStatefulWidget {
  const JobberBookingScreen({super.key, required this.booking, this.now});

  final JobberBooking booking;

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<JobberBookingScreen> createState() => _JobberBookingScreenState();
}

class _JobberBookingScreenState extends ConsumerState<JobberBookingScreen> {
  // Held only while this screen is open: the address is never kept in the app state.
  ReleasedAddress? _address;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final controller = ref.read(applicationsControllerProvider.notifier)..clearError();
      if (widget.booking.status == 'completed') controller.loadReview(widget.booking.id);
    });
  }

  /// The freshest copy of the job: the list reloads after each change.
  JobberBooking _current(ApplicationsState state) {
    for (final row in state.bookings ?? const <JobberBooking>[]) {
      if (row.id == widget.booking.id) return row;
    }
    return widget.booking;
  }

  Future<void> _checkIn() async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome =
        await ref.read(applicationsControllerProvider.notifier).checkIn(widget.booking.id);
    if (outcome == CheckInOutcome.withoutPosition && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text(ApplicationCopy.arrivedWithoutPosition)),
      );
    }
  }

  Future<void> _checkOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ApplicationCopy.finishedTitle),
        content: const Text(ApplicationCopy.finishedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(ApplicationCopy.notYet),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(ApplicationCopy.finished),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(applicationsControllerProvider.notifier).checkOut(widget.booking.id);
  }

  Future<void> _showAddress() async {
    final address =
        await ref.read(applicationsControllerProvider.notifier).address(widget.booking.id);
    if (address != null && mounted) setState(() => _address = address);
  }

  Future<void> _copy(ReleasedAddress address) async {
    await Clipboard.setData(ClipboardData(text: '${address.latitude}, ${address.longitude}'));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ApplicationCopy.pinCopied)));
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ApplicationCopy.cancelParticipationTitle),
        content: const Text(ApplicationCopy.cancelParticipationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(ApplicationCopy.keep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(ApplicationCopy.cancelParticipation),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await ref
        .read(applicationsControllerProvider.notifier)
        .cancelBooking(widget.booking.id, '');
    if (done && mounted) Navigator.of(context).pop();
  }

  IconData _icon(String status) => switch (status) {
        'checked_in' => Icons.play_circle_outline,
        'completed' => Icons.check_circle_outline,
        'disputed' => Icons.report_problem_outlined,
        'cancelled' || 'expired' => Icons.cancel_outlined,
        _ => Icons.schedule,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(applicationsControllerProvider);
    final booking = _current(state);
    final now = widget.now ?? DateTime.now();
    final beforeJob = booking.status == 'confirmed' || booking.status == 'address_released';
    final open =
        beforeJob && booking.payment == 'confirmed' && !now.isBefore(booking.addressAvailableFrom);
    final canCheckIn = ApplicationCopy.canCheckIn(booking, now);
    final payout = ApplicationCopy.payoutLine(booking);
    final address = _address;
    return FlowScaffold(
      title: ApplicationCopy.jobTitle,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            icon: open ? Icons.place_outlined : _icon(booking.status),
            label: ApplicationCopy.jobStatus(booking, now),
            strong: open,
          ),
        ),
        const SizedBox(height: Gaps.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(booking.categoryName, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gaps.sm),
              MetaChip(
                icon: Icons.event_outlined,
                label: formatWhen(booking.startsAt, booking.durationMinutes),
              ),
              const SizedBox(height: Gaps.xs),
              MetaChip(icon: Icons.payments_outlined, label: formatXof(booking.payXof)),
              const SizedBox(height: Gaps.xs),
              MetaChip(
                icon: Icons.place_outlined,
                label: '${booking.commune} · ${booking.quartier}',
              ),
            ],
          ),
        ),
        if (address != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ApplicationCopy.addressTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gaps.sm),
                Text('${address.commune} · ${address.quartier}', style: theme.textTheme.bodyLarge),
                Text(
                  '${address.latitude.toStringAsFixed(5)}, ${address.longitude.toStringAsFixed(5)}',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: Gaps.sm),
                OutlinedButton(
                  onPressed: () => _copy(address),
                  child: const Text(ApplicationCopy.copyPin),
                ),
              ],
            ),
          )
        else if (open && canCheckIn)
          // Arriving is the main action now; the address stays one tap away.
          OutlinedButton(
            onPressed: state.sending ? null : _showAddress,
            child: const Text(ApplicationCopy.seeAddress),
          )
        else if (open)
          FilledButton(
            onPressed: state.sending ? null : _showAddress,
            child: const Text(ApplicationCopy.seeAddress),
          ),
        const SizedBox(height: Gaps.md),
        if (canCheckIn) ...[
          BusyButton(
            label: ApplicationCopy.arrived,
            onPressed: _checkIn,
            busy: state.sending,
          ),
          const SizedBox(height: Gaps.md),
        ],
        if (booking.status == 'checked_in') ...[
          BusyButton(
            label: ApplicationCopy.finished,
            onPressed: _checkOut,
            busy: state.sending,
          ),
          const SizedBox(height: Gaps.md),
        ],
        if (payout != null)
          AppCard(
            child: Row(
              children: [
                Icon(booking.payout == 'paid' ? Icons.check_circle_outline : Icons.schedule),
                const SizedBox(width: Gaps.md),
                Expanded(child: Text(payout, style: theme.textTheme.titleMedium)),
              ],
            ),
          ),
        if (booking.status == 'completed')
          ReviewSection(target: JobTarget.jobber(booking.id), reviewable: booking.reviewable),
        if (ApplicationCopy.jobReportable(booking)) ...[
          OutlinedButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ReportScreen(
                  target: JobTarget.jobber(booking.id),
                  canDispute:
                      booking.status == 'checked_in' || booking.status == 'completion_pending',
                ),
              ),
            ),
            child: const Text(ApplicationCopy.reportProblem),
          ),
          const SizedBox(height: Gaps.md),
        ],
        if (ApplicationCopy.jobCancellable(booking))
          OutlinedButton(
            onPressed: state.sending ? null : _cancel,
            child: const Text(ApplicationCopy.cancelParticipation),
          ),
      ],
    );
  }
}
