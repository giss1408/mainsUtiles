import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;
import 'section_bar.dart';
import 'staff_profile_screen.dart';

/// The payments staff have to check, or to refund. No reference and no name are listed.
class PaymentsQueueScreen extends StatelessWidget {
  const PaymentsQueueScreen({
    super.key,
    required this.state,
    required this.onTab,
    required this.onRefresh,
    required this.onOpen,
    required this.onSignOut,
    this.onSection,
  });

  final StaffState state;
  final ValueChanged<String> onTab;
  final Future<void> Function() onRefresh;
  final ValueChanged<PaymentItem> onOpen;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;

  @override
  Widget build(BuildContext context) {
    final me = state.me;
    // The refund tab only for those who may record a refund, the check tab for those who may check.
    final tabs = [
      for (final tab in StaffCopy.paymentTabs)
        if (me == null || me.can(tab.$1 == 'check' ? 'verify_payment' : 'make_refund')) tab,
    ];
    final initial = tabs.indexWhere((t) => t.$1 == state.paymentTab);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(StaffCopy.paymentsTitle),
          actions: [
            IconButton(
              tooltip: StaffCopy.profileTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StaffProfileScreen(me: state.me, onSignOut: onSignOut),
                ),
              ),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
          bottom: tabs.length < 2
              ? null
              : TabBar(
                  onTap: (index) => onTab(tabs[index].$1),
                  tabs: [for (final tab in tabs) Tab(text: tab.$2)],
                ),
        ),
        bottomNavigationBar:
            sectionBar(me: state.me, section: StaffSection.payments, onSection: onSection),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: RefreshIndicator(onRefresh: onRefresh, child: _list(context)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final rows = state.payments;
    final children = <Widget>[
      if (state.listError != null) ...[
        MessageBanner(
          message: state.listError!,
          actionLabel: StaffCopy.retry,
          onAction: onRefresh,
        ),
        const SizedBox(height: Gaps.lg),
      ],
      if (rows == null)
        for (var i = 0; i < 3; i++) const _Skeleton()
      else if (rows.isEmpty && state.listError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gaps.xxxl),
          child: Text(
            StaffCopy.paymentsEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        )
      else
        for (final row in rows) _Row(item: row, onTap: () => onOpen(row)),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gaps.lg),
      children: children,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onTap});

  final PaymentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
      side: const BorderSide(color: AppColors.border),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Material(
        color: AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatXof(item.amountXof), style: theme.textTheme.titleMedium),
                      const SizedBox(height: Gaps.xs),
                      Text(
                        '${item.categoryName} · ${item.methodLabel}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                      Text(
                        StaffCopy.age(item.submittedAt, DateTime.now()),
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                      if (item.late) ...[
                        const SizedBox(height: Gaps.sm),
                        const StatusPill(icon: Icons.warning_amber_rounded, label: StaffCopy.late),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gaps.sm),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: Gaps.sm),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
