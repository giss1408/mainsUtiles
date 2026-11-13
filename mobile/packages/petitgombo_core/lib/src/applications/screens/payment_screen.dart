import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../offers/offer_format.dart';
import '../../verification/capture.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../application_models.dart';
import '../booking_controller.dart';
import '../proof_picker.dart';

/// Where to pay, then the proof: a method, the transaction reference and a screenshot.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _reference = TextEditingController();
  int? _methodId;
  CapturedPhoto? _screenshot;
  String? _pickError;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(bookingControllerProvider(widget.offerId).notifier).clearError());
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final photo = await ref.read(proofPickerProvider).pick();
      if (photo != null && mounted) {
        setState(() {
          _screenshot = photo;
          _pickError = null;
        });
      }
    } on FormatException {
      if (mounted) setState(() => _pickError = ApplicationCopy.imageUnreadable);
    }
  }

  Future<void> _send() async {
    final sent = await ref.read(bookingControllerProvider(widget.offerId).notifier).submitProof(
        methodId: _methodId!, reference: _reference.text.trim(), screenshot: _screenshot!);
    if (sent && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _copy(PaymentMethodInfo method) async {
    await Clipboard.setData(ClipboardData(text: method.number));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(ApplicationCopy.copied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(bookingControllerProvider(widget.offerId));
    final detail = state.detail;
    if (detail == null) {
      return const FlowScaffold(
          title: ApplicationCopy.payTitle, children: [Text(ApplicationCopy.gone)]);
    }
    final ready = _methodId != null && _reference.text.trim().isNotEmpty && _screenshot != null;
    return FlowScaffold(
      title: ApplicationCopy.payTitle,
      banner: state.error != null
          ? MessageBanner(message: state.error!)
          : _pickError == null
              ? null
              : MessageBanner(message: _pickError!),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ApplicationCopy.amountLabel, style: theme.textTheme.bodySmall),
              Text(formatXof(detail.amountXof), style: theme.textTheme.headlineMedium),
            ],
          ),
        ),
        Text(ApplicationCopy.payBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.md),
        for (final method in detail.methods)
          AppCard(
            onTap: () => setState(() => _methodId = method.id),
            child: Row(
              children: [
                Icon(
                  _methodId == method.id ? Icons.radio_button_checked : Icons.radio_button_off,
                  semanticLabel: method.providerLabel,
                ),
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.providerLabel, style: theme.textTheme.titleMedium),
                      Text(method.number, style: theme.textTheme.bodyLarge),
                      if (method.accountName.isNotEmpty)
                        Text(method.accountName, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: ApplicationCopy.copy,
                  onPressed: () => _copy(method),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gaps.md),
        TextField(
          key: const Key('payment-reference'),
          controller: _reference,
          maxLength: 40,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: ApplicationCopy.referenceLabel,
            helperText: ApplicationCopy.referenceHint,
            counterText: '',
          ),
        ),
        const SizedBox(height: Gaps.lg),
        if (_screenshot != null) ...[
          _Preview(bytes: _screenshot!.bytes),
          const SizedBox(height: Gaps.sm),
        ],
        OutlinedButton(
          onPressed: state.sending ? null : _pick,
          child: Text(_screenshot == null
              ? ApplicationCopy.pickScreenshot
              : ApplicationCopy.changeScreenshot),
        ),
        const SizedBox(height: Gaps.lg),
        BusyButton(
          label: ApplicationCopy.sendProof,
          onPressed: ready ? _send : null,
          busy: state.sending,
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: SizedBox(
        height: 160,
        child:
            Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
      ),
    );
  }
}
