import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../ops_controller.dart';
import '../providers.dart';
import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'ops_widgets.dart';

/// The messages to send on WhatsApp, urgent first. No text and no number are listed.
class MessagesQueueScreen extends StatelessWidget {
  const MessagesQueueScreen({
    super.key,
    required this.state,
    required this.me,
    required this.onRefresh,
    required this.onOpen,
    required this.onSignOut,
    this.onSection,
    this.now,
  });

  final OpsState state;
  final StaffMe? me;
  final Future<void> Function() onRefresh;
  final ValueChanged<MessageItem> onOpen;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return OpsQueueScaffold(
      title: StaffCopy.messagesTitle,
      section: StaffSection.messages,
      me: me,
      onRefresh: onRefresh,
      onSignOut: onSignOut,
      onSection: onSection,
      children: queueBody<MessageItem>(
        context,
        rows: state.messages,
        listError: state.listError,
        empty: StaffCopy.messagesEmpty,
        onRefresh: onRefresh,
        row: (item) => QueueRow(
          title: item.kindLabel,
          lines: [
            StaffCopy.recipient(item.recipientRole),
            StaffCopy.age(item.createdAt, now ?? DateTime.now()),
          ],
          pills: [
            if (item.urgent)
              const StatusPill(icon: Icons.bolt_outlined, label: StaffCopy.urgent, strong: true),
            if (item.late) latePill,
          ],
          onTap: () => onOpen(item),
        ),
      ),
    );
  }
}

/// One message: what will be said, and the one action to take. The number is never shown: it is
/// inside the WhatsApp link, which is opened and dropped.
class MessageDetailScreen extends StatefulWidget {
  const MessageDetailScreen({
    super.key,
    required this.item,
    required this.onBack,
    required this.onSend,
    this.opener = openExternally,
    this.sendable = true,
    this.busy = false,
    this.error,
    this.now,
  });

  final MessageItem item;
  final VoidCallback onBack;

  /// Marks the message sent; returns the WhatsApp link, or null when the server refused.
  final Future<Uri?> Function() onSend;
  final UrlOpener opener;

  /// False once the message has left the queue: sent, or withdrawn by the server.
  final bool sendable;
  final bool busy;
  final String? error;
  final DateTime? now;

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  bool _whatsAppMissing = false;

  Future<void> _send() async {
    setState(() => _whatsAppMissing = false);
    final uri = await widget.onSend();
    if (!mounted || uri == null) return;
    final opened = await widget.opener(uri);
    if (!mounted) return;
    if (opened) {
      widget.onBack();
    } else {
      setState(() => _whatsAppMissing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return OpsDetailScaffold(
      title: StaffCopy.messageDetailTitle,
      onBack: widget.onBack,
      error: _whatsAppMissing ? StaffCopy.noWhatsApp : widget.error,
      children: [
        Text(item.kindLabel, style: theme.textTheme.headlineMedium),
        const SizedBox(height: Gaps.sm),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.xs,
          children: [
            StatusPill(icon: Icons.person_outline, label: StaffCopy.recipient(item.recipientRole)),
            if (item.urgent)
              const StatusPill(icon: Icons.bolt_outlined, label: StaffCopy.urgent, strong: true),
            if (item.late) latePill,
          ],
        ),
        const SizedBox(height: Gaps.lg),
        DetailField(StaffCopy.fieldJob, item.categoryName ?? '…'),
        DetailField(
          StaffCopy.fieldWaiting,
          StaffCopy.age(item.createdAt, widget.now ?? DateTime.now()),
        ),
        Text(StaffCopy.fieldMessage, style: theme.textTheme.bodySmall),
        const SizedBox(height: Gaps.xs),
        AppCard(child: Text(item.text ?? '…', style: theme.textTheme.bodyLarge)),
        const SizedBox(height: Gaps.lg),
        if (widget.busy) const LinearProgressIndicator(),
        FilledButton.icon(
          onPressed: widget.busy || !widget.sendable || item.text == null ? null : _send,
          icon: const Icon(Icons.send),
          label: const Text(StaffCopy.openWhatsApp),
        ),
        const SizedBox(height: Gaps.md),
        Text(StaffCopy.messageReady, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Gaps.sm),
        Text(StaffCopy.officialOnly, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
