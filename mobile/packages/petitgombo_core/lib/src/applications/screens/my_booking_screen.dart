import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../offers/offer_copy.dart';
import '../../offers/offer_format.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../booking_controller.dart';
import 'payment_screen.dart';

/// The booking of one offer: who is coming, what to pay, and the actions its state allows.
class MyBookingScreen extends ConsumerStatefulWidget {
  const MyBookingScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<MyBookingScreen> createState() => _MyBookingScreenState();
}

class _MyBookingScreenState extends ConsumerState<MyBookingScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final controller = ref.read(bookingControllerProvider(widget.offerId).notifier);
      await controller.load();
      final detail = ref.read(bookingControllerProvider(widget.offerId)).detail;
      if (mounted && detail != null && detail.hasPhoto) await controller.loadPhoto();
    });
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ApplicationCopy.cancelBookingTitle),
        content: const Text(ApplicationCopy.cancelBookingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(ApplicationCopy.keep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(ApplicationCopy.cancelBooking),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await ref.read(bookingControllerProvider(widget.offerId).notifier).cancel('');
    if (done && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(bookingControllerProvider(widget.offerId));
    final detail = state.detail;
    final banner = state.error == null
        ? null
        : MessageBanner(
            message: state.error!,
            actionLabel: OfferCopy.retry,
            onAction: ref.read(bookingControllerProvider(widget.offerId).notifier).load,
          );
    if (detail == null) {
      return FlowScaffold(
        title: ApplicationCopy.myBooking,
        banner: banner,
        children: [
          if (state.loading || state.error != null)
            const Center(child: CircularProgressIndicator())
          else
            const Text(ApplicationCopy.gone),
        ],
      );
    }
    final confirmed = detail.status != 'accepted' && detail.status != 'payment_review';
    final canPay = detail.status == 'accepted';
    return FlowScaffold(
      title: ApplicationCopy.myBooking,
      banner: banner,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            icon: confirmed ? Icons.check_circle_outline : Icons.schedule,
            label: ApplicationCopy.bookingStatusLine(detail),
            strong: confirmed,
          ),
        ),
        const SizedBox(height: Gaps.lg),
        AppCard(
          child: Row(
            children: [
              if (state.photo != null)
                ClipOval(
                  child: Image.memory(
                    state.photo!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const IconTile(icon: Icons.person_outline, size: 56),
                  ),
                )
              else
                const IconTile(icon: Icons.person_outline, size: 56),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.jobberFullName ?? detail.jobberFirstName,
                        style: theme.textTheme.titleMedium),
                    if (detail.hasPhoto)
                      Text(ApplicationCopy.photoLabel, style: theme.textTheme.bodySmall),
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
              Text(ApplicationCopy.amountLabel, style: theme.textTheme.bodySmall),
              Text(formatXof(detail.amountXof), style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        if (canPay) ...[
          FilledButton(
            onPressed: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => PaymentScreen(offerId: widget.offerId)),
              );
            },
            child: Text(
              detail.payment != null && detail.payment!.refused
                  ? ApplicationCopy.payAgain
                  : ApplicationCopy.pay,
            ),
          ),
          const SizedBox(height: Gaps.md),
        ],
        if (detail.cancellable)
          OutlinedButton(
            onPressed: state.sending ? null : _cancel,
            child: const Text(ApplicationCopy.cancelBooking),
          ),
      ],
    );
  }
}
