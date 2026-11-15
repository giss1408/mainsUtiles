import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../ops_controller.dart';
import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'ops_widgets.dart';

/// What follows a job: the payouts to make and the open disputes. No phone and no text are listed.
class JobsQueueScreen extends StatelessWidget {
  const JobsQueueScreen({
    super.key,
    required this.state,
    required this.me,
    required this.onTab,
    required this.onRefresh,
    required this.onOpenPayout,
    required this.onOpenDispute,
    required this.onSignOut,
    this.onSection,
    this.now,
  });

  final OpsState state;
  final StaffMe? me;
  final ValueChanged<String> onTab;
  final Future<void> Function() onRefresh;
  final ValueChanged<PayoutItem> onOpenPayout;
  final ValueChanged<DisputeItem> onOpenDispute;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final holder = me;
    final tabs = [
      for (final tab in StaffCopy.jobsTabs)
        if (holder == null || holder.can(tab.$1 == 'payouts' ? 'make_payout' : 'resolve_dispute'))
          tab,
    ];
    final disputes = state.jobsTab == 'disputes';
    final far = state.alerts?.farCheckins ?? 0;
    final clock = now ?? DateTime.now();
    return OpsQueueScaffold(
      title: StaffCopy.jobsTitle,
      section: StaffSection.jobs,
      me: me,
      onRefresh: onRefresh,
      onSignOut: onSignOut,
      onSection: onSection,
      tabs: tabs,
      tab: state.jobsTab,
      onTab: onTab,
      children: [
        if (far > 0) ...[
          MessageBanner(message: StaffCopy.farCheckins(far)),
          const SizedBox(height: Gaps.lg),
        ],
        if (disputes)
          ...queueBody<DisputeItem>(
            context,
            rows: state.disputes,
            listError: state.listError,
            empty: StaffCopy.disputesEmpty,
            onRefresh: onRefresh,
            row: (item) => QueueRow(
              title: item.categoryName,
              lines: [StaffCopy.age(item.createdAt, clock)],
              pills: [if (item.late) latePill],
              onTap: () => onOpenDispute(item),
            ),
          )
        else
          ...queueBody<PayoutItem>(
            context,
            rows: state.payouts,
            listError: state.listError,
            empty: StaffCopy.payoutsEmpty,
            onRefresh: onRefresh,
            row: (item) => QueueRow(
              title: formatXof(item.amountXof),
              lines: [item.categoryName, StaffCopy.age(item.dueAt, clock)],
              pills: [if (item.late) latePill],
              onTap: () => onOpenPayout(item),
            ),
          ),
      ],
    );
  }
}

/// One payout: how much, to which number, and the reference to record once the money is sent.
class PayoutDetailScreen extends StatefulWidget {
  const PayoutDetailScreen({
    super.key,
    required this.item,
    required this.onBack,
    required this.onPay,
    this.busy = false,
    this.error,
    this.now,
  });

  final PayoutItem item;
  final VoidCallback onBack;
  final Future<bool> Function(String reference) onPay;
  final bool busy;
  final String? error;
  final DateTime? now;

  @override
  State<PayoutDetailScreen> createState() => _PayoutDetailScreenState();
}

class _PayoutDetailScreenState extends State<PayoutDetailScreen> {
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final phone = item.jobberPhone;
    final blocked = item.payable == false;
    final ready = phone != null && !blocked && _reference.text.trim().length >= 4;
    return OpsDetailScaffold(
      title: StaffCopy.payoutDetailTitle,
      onBack: widget.onBack,
      error: widget.error,
      children: [
        Text(formatXof(item.amountXof), style: theme.textTheme.headlineMedium),
        const SizedBox(height: Gaps.lg),
        DetailField(StaffCopy.fieldPayoutAmount, formatXof(item.amountXof)),
        DetailField(StaffCopy.fieldJobberPhone, phone == null ? '…' : StaffCopy.phone(phone)),
        DetailField(StaffCopy.fieldJob, item.categoryName),
        if (item.completedAt != null)
          DetailField(
            StaffCopy.fieldCompleted,
            StaffCopy.age(item.completedAt!, widget.now ?? DateTime.now()),
          ),
        if (item.late) ...[
          const Align(alignment: Alignment.centerLeft, child: latePill),
          const SizedBox(height: Gaps.md),
        ],
        if (blocked)
          const MessageBanner(message: StaffCopy.notPayable)
        else ...[
          Text(StaffCopy.payoutHow, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gaps.md),
          TextField(
            key: const Key('payout-reference'),
            controller: _reference,
            maxLength: 40,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: StaffCopy.payoutReference,
              counterText: '',
            ),
          ),
          const SizedBox(height: Gaps.lg),
          if (widget.busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: widget.busy || !ready ? null : () => widget.onPay(_reference.text.trim()),
            child: const Text(StaffCopy.recordPayout),
          ),
        ],
      ],
    );
  }
}

/// One dispute: what was written, what happened, and the decision. Names are first names only.
class DisputeDetailScreen extends StatefulWidget {
  const DisputeDetailScreen({
    super.key,
    required this.item,
    required this.onBack,
    required this.onResolve,
    this.busy = false,
    this.error,
    this.now,
  });

  final DisputeItem item;
  final VoidCallback onBack;
  final Future<bool> Function(String outcome, String note, {int? jobberXof}) onResolve;
  final bool busy;
  final String? error;
  final DateTime? now;

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  final _note = TextEditingController();
  final _share = TextEditingController();
  String? _outcome;

  @override
  void dispose() {
    _note.dispose();
    _share.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_share.text.trim());

  bool get _ready {
    if (_outcome == null || _note.text.trim().isEmpty || widget.item.text == null) return false;
    if (_outcome != 'split') return true;
    final amount = _amount;
    final price = widget.item.payXof;
    return amount != null && price != null && amount > 0 && amount < price;
  }

  Future<void> _resolve() async {
    final outcome = _outcome!;
    final label = StaffCopy.outcomes.firstWhere((o) => o.$1 == outcome).$2;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(StaffCopy.resolveTitle),
        content: Text('$label. ${StaffCopy.resolveBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(StaffCopy.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(StaffCopy.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onResolve(
      outcome,
      _note.text.trim(),
      jobberXof: outcome == 'split' ? _amount : null,
    );
  }

  String _time(DateTime? value) =>
      value == null ? StaffCopy.notRecorded : '${formatDay(value)} à ${formatClock(value)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final distance = item.distanceM;
    return OpsDetailScaffold(
      title: StaffCopy.disputeDetailTitle,
      onBack: widget.onBack,
      error: widget.error,
      children: [
        Text(item.categoryName, style: theme.textTheme.headlineMedium),
        if (item.late) ...[
          const SizedBox(height: Gaps.sm),
          const Align(alignment: Alignment.centerLeft, child: latePill),
        ],
        const SizedBox(height: Gaps.lg),
        DetailField(StaffCopy.fieldWrittenBy, StaffCopy.side(item.authorSide)),
        AppCard(child: Text(item.text ?? '…', style: theme.textTheme.bodyLarge)),
        const SizedBox(height: Gaps.md),
        DetailField(
          StaffCopy.fieldPeople,
          '${item.householderName ?? '…'} · ${item.jobberName ?? '…'}',
        ),
        DetailField(StaffCopy.fieldPrice, item.payXof == null ? '…' : formatXof(item.payXof!)),
        DetailField(StaffCopy.fieldArrival, _time(item.checkedInAt)),
        DetailField(StaffCopy.fieldDeparture, _time(item.checkedOutAt)),
        DetailField(
          StaffCopy.fieldDistance,
          distance == null
              ? StaffCopy.notRecorded
              : '$distance m${item.far ? ' (${StaffCopy.farFromHome})' : ''}',
        ),
        DetailField(StaffCopy.fieldHouseholdPayment, item.paymentState ?? '…'),
        const SizedBox(height: Gaps.md),
        Text(StaffCopy.decision, style: theme.textTheme.titleMedium),
        for (final outcome in StaffCopy.outcomes)
          RadioListTile<String>(
            value: outcome.$1,
            groupValue: _outcome,
            onChanged: widget.busy ? null : (value) => setState(() => _outcome = value),
            title: Text(outcome.$2),
            contentPadding: EdgeInsets.zero,
          ),
        if (_outcome == 'split') ...[
          TextField(
            key: const Key('dispute-share'),
            controller: _share,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: StaffCopy.jobberShare),
          ),
          const SizedBox(height: Gaps.md),
        ],
        TextField(
          key: const Key('dispute-note'),
          controller: _note,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: StaffCopy.decisionNote, counterText: ''),
        ),
        const SizedBox(height: Gaps.lg),
        if (widget.busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: widget.busy || !_ready ? null : _resolve,
          child: const Text(StaffCopy.resolve),
        ),
      ],
    );
  }
}
