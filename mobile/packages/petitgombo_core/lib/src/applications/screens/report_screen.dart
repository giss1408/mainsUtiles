import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../job_target.dart';

/// "Signaler un problème": a few words, sent either as a dispute (the payment is frozen and
/// staff decide) or as a private remark that the other side never hears about.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.target, required this.canDispute});

  final JobTarget target;

  /// False once the job is completed or already disputed: only a private remark is left.
  final bool canDispute;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _text = TextEditingController();
  late bool _dispute = widget.canDispute;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.target.clearError(ref));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final sent = await widget.target.report(ref, _text.text.trim(), dispute: _dispute);
    if (!sent || !mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text(ApplicationCopy.reportSent)));
    navigator.pop(true);
  }

  Widget _choice(bool dispute, String label) => AppCard(
        onTap: () => setState(() => _dispute = dispute),
        child: Row(
          children: [
            Icon(_dispute == dispute ? Icons.radio_button_checked : Icons.radio_button_off),
            const SizedBox(width: Gaps.md),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final error = widget.target.error(ref);
    final ready = _text.text.trim().length >= 3;
    return FlowScaffold(
      title: ApplicationCopy.reportTitle,
      banner: error == null ? null : MessageBanner(message: error),
      children: [
        TextField(
          key: const Key('report-text'),
          controller: _text,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: ApplicationCopy.reportLabel,
            helperText: ApplicationCopy.reportHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: Gaps.md),
        if (widget.canDispute) ...[
          _choice(true, ApplicationCopy.reportDispute),
          _choice(false, ApplicationCopy.reportConcern),
        ],
        const PrivacyNote(ApplicationCopy.reportConcernNote),
        const SizedBox(height: Gaps.lg),
        BusyButton(
          label: ApplicationCopy.reportSend,
          onPressed: ready ? _send : null,
          busy: widget.target.sending(ref),
        ),
      ],
    );
  }
}
