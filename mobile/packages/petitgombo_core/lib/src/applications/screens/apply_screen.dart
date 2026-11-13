import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../offers/offer_format.dart';
import '../../offers/offer_models.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../applications_controller.dart';

/// Writes an optional word to the household, then sends the application.
class ApplyScreen extends ConsumerStatefulWidget {
  const ApplyScreen({super.key, required this.offer});

  final PublicOffer offer;

  @override
  ConsumerState<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends ConsumerState<ApplyScreen> {
  static const _maxLength = 200;

  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(applicationsControllerProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final receipt = await ref
        .read(applicationsControllerProvider.notifier)
        .apply(widget.offer.id, _message.text.trim());
    if (receipt != null && mounted) Navigator.of(context).pop(receipt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(applicationsControllerProvider);
    final offer = widget.offer;
    return FlowScaffold(
      title: ApplicationCopy.applyTitle,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(offer.categoryName, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gaps.sm),
              MetaChip(
                icon: Icons.event_outlined,
                label: formatWhen(offer.startsAt, offer.durationMinutes),
              ),
              const SizedBox(height: Gaps.xs),
              MetaChip(icon: Icons.payments_outlined, label: formatXof(offer.payXof)),
            ],
          ),
        ),
        Text(ApplicationCopy.applyBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.md),
        TextField(
          key: const Key('apply-message'),
          controller: _message,
          maxLength: _maxLength,
          maxLines: 4,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: ApplicationCopy.messageLabel),
        ),
        const SizedBox(height: Gaps.lg),
        BusyButton(label: ApplicationCopy.send, onPressed: _send, busy: state.sending),
      ],
    );
  }
}
