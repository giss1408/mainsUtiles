import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../providers.dart';
import '../staff_api.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;

/// One trusted contact: who to write to, and the one action to take. The number is never shown:
/// it is inside the WhatsApp link, which is opened and dropped.
class ContactDetailScreen extends StatefulWidget {
  const ContactDetailScreen({
    super.key,
    required this.item,
    required this.onBack,
    required this.onSend,
    required this.onNotice,
    this.opener = openExternally,
    this.busy = false,
    this.error,
    this.now,
  });

  final ContactItem item;
  final VoidCallback onBack;

  /// Issues the code; returns the WhatsApp link, or null on failure.
  final Future<Uri?> Function() onSend;

  /// Records the notice; returns the WhatsApp link, or null on failure.
  final Future<Uri?> Function() onNotice;
  final UrlOpener opener;
  final bool busy;
  final String? error;
  final DateTime? now;

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  bool _whatsAppMissing = false;

  Future<void> _act() async {
    setState(() => _whatsAppMissing = false);
    final notice = widget.item.action == 'notice';
    final uri = await (notice ? widget.onNotice() : widget.onSend());
    if (uri == null) return;
    final opened = await widget.opener(uri);
    if (mounted && !opened) setState(() => _whatsAppMissing = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final notice = item.action == 'notice';
    final message = _whatsAppMissing ? StaffCopy.noWhatsApp : widget.error;
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
          title: const Text(StaffCopy.contactDetailTitle),
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
                    Text(item.name ?? '…', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Gaps.lg),
                    _Field(StaffCopy.fieldContactLink,
                        StaffCopy.contactRelationship(item.relationship)),
                    _Field(StaffCopy.fieldJobber, item.jobberName ?? ''),
                    _Field(
                      StaffCopy.fieldCreated,
                      StaffCopy.age(item.createdAt, widget.now ?? DateTime.now()),
                    ),
                    const SizedBox(height: Gaps.xl),
                    if (widget.busy) const LinearProgressIndicator(),
                    FilledButton.icon(
                      onPressed: widget.busy ? null : _act,
                      icon: const Icon(Icons.send),
                      label: Text(notice ? StaffCopy.sendNotice : StaffCopy.sendContactCode),
                    ),
                    const SizedBox(height: Gaps.md),
                    Text(
                      notice ? StaffCopy.noticeNote : StaffCopy.doNotCopyCode,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Gaps.sm),
                    Text(StaffCopy.officialOnly, style: theme.textTheme.bodyMedium),
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
