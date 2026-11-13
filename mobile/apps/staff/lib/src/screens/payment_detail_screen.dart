import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;
import 'reason_dialog.dart';

/// One payment: the amount, the number it went to, the reference the householder typed and the
/// receipt image. Staff compare them with the platform account's own history, then decide.
class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen({
    super.key,
    required this.item,
    required this.me,
    required this.onBack,
    required this.onConfirm,
    required this.onRefuse,
    required this.onRefund,
    this.proof,
    this.busy = false,
    this.error,
  });

  final PaymentItem item;
  final StaffMe me;
  final VoidCallback onBack;
  final Future<bool> Function({required bool amountMatches, required bool referenceMatches})
      onConfirm;
  final Future<bool> Function(String reason) onRefuse;
  final Future<bool> Function(String reference) onRefund;

  /// The receipt image, once loaded.
  final Uint8List? proof;
  final bool busy;
  final String? error;

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  bool _amount = false;
  bool _reference = false;

  Future<void> _refuse() async {
    final reason = await showReasonDialog(context, title: StaffCopy.refusePayment);
    if (reason != null) await widget.onRefuse(reason);
  }

  Future<void> _refund() async {
    final reference = await showReasonDialog(context, title: StaffCopy.refundReference);
    if (reference != null) await widget.onRefund(reference);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final refund = item.action == 'refund';
    final canDecide = widget.me.can(refund ? 'make_refund' : 'verify_payment');
    final total = formatXof(item.amountXof);
    final fee = item.feeXof ?? 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: StaffCopy.back,
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(StaffCopy.paymentDetailTitle),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Gaps.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.error != null) ...[
                      MessageBanner(message: widget.error!),
                      const SizedBox(height: Gaps.lg),
                    ],
                    Text(total, style: theme.textTheme.headlineMedium),
                    if (fee > 0)
                      Text('dont ${formatXof(fee)} de frais', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Gaps.lg),
                    _Field(StaffCopy.fieldAmount, total),
                    _Field(
                      StaffCopy.fieldMethod,
                      '${item.methodLabel} ${item.methodNumber ?? ''}'.trim(),
                    ),
                    if (!refund) _Field(StaffCopy.fieldReference, item.reference ?? '…'),
                    if (item.seenBefore == true)
                      const Padding(
                        padding: EdgeInsets.only(bottom: Gaps.md),
                        child: MessageBanner(message: StaffCopy.seenBefore),
                      ),
                    if (!refund) ...[
                      Text(StaffCopy.checkHistory, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: Gaps.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.card),
                        child: widget.proof == null
                            ? const SizedBox(
                                height: 120,
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : Image.memory(
                                widget.proof!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Padding(
                                  padding: EdgeInsets.all(Gaps.lg),
                                  child: Text(StaffCopy.proofMissing),
                                ),
                              ),
                      ),
                      const SizedBox(height: Gaps.lg),
                    ],
                    if (widget.busy) const LinearProgressIndicator(),
                    if (canDecide && !refund) ...[
                      CheckboxListTile(
                        value: _amount,
                        onChanged: widget.busy ? null : (v) => setState(() => _amount = v ?? false),
                        title: const Text(StaffCopy.amountMatches),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _reference,
                        onChanged:
                            widget.busy ? null : (v) => setState(() => _reference = v ?? false),
                        title: const Text(StaffCopy.referenceMatches),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: Gaps.md),
                      FilledButton(
                        onPressed: widget.busy || !(_amount && _reference)
                            ? null
                            : () => widget.onConfirm(
                                amountMatches: _amount, referenceMatches: _reference),
                        child: const Text(StaffCopy.confirmPayment),
                      ),
                      const SizedBox(height: Gaps.md),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        onPressed: widget.busy ? null : _refuse,
                        child: const Text(StaffCopy.refusePayment),
                      ),
                    ],
                    if (canDecide && refund)
                      FilledButton(
                        onPressed: widget.busy ? null : _refund,
                        child: const Text(StaffCopy.recordRefund),
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

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value.isEmpty ? '—' : value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
