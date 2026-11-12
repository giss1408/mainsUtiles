import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../providers.dart';
import '../staff_api.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;
import 'reason_dialog.dart';

class EnrolmentDetailScreen extends StatefulWidget {
  const EnrolmentDetailScreen({
    super.key,
    required this.item,
    required this.me,
    required this.onBack,
    required this.onApprove,
    required this.onRefuse,
    required this.onHold,
    required this.onSend,
    this.opener = openExternally,
    this.busy = false,
    this.error,
    this.now,
  });

  final EnrolmentItem item;
  final StaffMe me;
  final VoidCallback onBack;
  final VoidCallback onApprove;
  final ValueChanged<String> onRefuse;
  final ValueChanged<String> onHold;

  /// Issues the confirmation number; returns the WhatsApp link, or null on failure.
  final Future<Uri?> Function() onSend;
  final UrlOpener opener;
  final bool busy;
  final String? error;
  final DateTime? now;

  @override
  State<EnrolmentDetailScreen> createState() => _EnrolmentDetailScreenState();
}

class _EnrolmentDetailScreenState extends State<EnrolmentDetailScreen> {
  bool _whatsAppMissing = false;

  Future<void> _send() async {
    setState(() => _whatsAppMissing = false);
    // The link carries the confirmation number: it is opened and then dropped.
    final uri = await widget.onSend();
    if (uri == null) return;
    final opened = await widget.opener(uri);
    if (mounted && !opened) setState(() => _whatsAppMissing = true);
  }

  Future<void> _withReason(String title, ValueChanged<String> action) async {
    final reason = await showReasonDialog(context, title: title);
    if (reason != null) action(reason);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final message = _whatsAppMissing ? StaffCopy.noWhatsApp : widget.error;
    final canReview = widget.me.can('review_enrolment');
    final canSend = widget.me.can('send_enrolment_code');
    final reviewable = item.status == 'pending' || item.status == 'held';
    final sendable = item.status == 'approved' || item.status == 'code_sent';
    final busy = widget.busy;

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
          title: const Text(StaffCopy.detailTitle),
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
                    if (message != null) ...[
                      MessageBanner(message: message),
                      const SizedBox(height: Gaps.lg),
                    ],
                    Text(StaffCopy.phone(item.phone), style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.lg),
                    _Field(StaffCopy.fieldStatus, StaffCopy.status(item.status)),
                    _Field(StaffCopy.fieldRole, StaffCopy.role(item.role)),
                    _Field(StaffCopy.fieldKind, StaffCopy.kind(item.kind)),
                    _Field(
                      StaffCopy.fieldDevice,
                      [item.deviceModel, item.platform].where((v) => v.isNotEmpty).join(' · '),
                    ),
                    _Field(StaffCopy.fieldIntegrity, StaffCopy.integrity(item.integrityVerdict)),
                    _Field(
                      StaffCopy.fieldCreated,
                      StaffCopy.age(item.createdAt, widget.now ?? DateTime.now()),
                    ),
                    if (item.reason != null) _Field(StaffCopy.fieldReason, item.reason!),
                    if (item.flags.isNotEmpty) ...[
                      const SizedBox(height: Gaps.sm),
                      Text(StaffCopy.fieldFlags, style: theme.textTheme.bodySmall),
                      const SizedBox(height: Gaps.xs),
                      for (final flag in item.flags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gaps.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                              const SizedBox(width: Gaps.sm),
                              Expanded(
                                child: Text(StaffCopy.flag(flag), style: theme.textTheme.bodyLarge),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: Gaps.xl),
                    if (busy) const LinearProgressIndicator(),
                    if (reviewable && canReview) ...[
                      FilledButton(
                        onPressed: busy ? null : widget.onApprove,
                        child: const Text(StaffCopy.approve),
                      ),
                      const SizedBox(height: Gaps.md),
                      OutlinedButton(
                        onPressed: busy ? null : () => _withReason(StaffCopy.hold, widget.onHold),
                        child: const Text(StaffCopy.hold),
                      ),
                      const SizedBox(height: Gaps.md),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        onPressed:
                            busy ? null : () => _withReason(StaffCopy.refuse, widget.onRefuse),
                        child: const Text(StaffCopy.refuse),
                      ),
                    ],
                    if (sendable && canSend) ...[
                      FilledButton.icon(
                        onPressed: busy ? null : _send,
                        icon: const Icon(Icons.send),
                        label: Text(item.status == 'approved' ? StaffCopy.send : StaffCopy.resend),
                      ),
                      const SizedBox(height: Gaps.md),
                      Text(StaffCopy.officialOnly, style: theme.textTheme.bodyMedium),
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
