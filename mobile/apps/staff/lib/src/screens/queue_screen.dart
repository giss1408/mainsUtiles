import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import 'staff_profile_screen.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'section_bar.dart';

/// Content never grows wider than this on tablets and desktops.
const double maxContentWidth = 720;

class QueueScreen extends StatelessWidget {
  const QueueScreen({
    super.key,
    required this.state,
    required this.onTab,
    required this.onRefresh,
    required this.onOpen,
    required this.onSignOut,
    this.onSection,
    this.now,
  });

  final StaffState state;
  final ValueChanged<String> onTab;
  final Future<void> Function() onRefresh;
  final ValueChanged<EnrolmentItem> onOpen;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final initial = StaffCopy.tabs.indexWhere((t) => t.$1 == state.tab);
    return DefaultTabController(
      length: StaffCopy.tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(StaffCopy.queueTitle),
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
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (index) => onTab(StaffCopy.tabs[index].$1),
            tabs: [for (final tab in StaffCopy.tabs) Tab(text: tab.$2)],
          ),
        ),
        bottomNavigationBar:
            sectionBar(me: state.me, section: StaffSection.enrolments, onSection: onSection),
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
    final items = state.items;
    final children = <Widget>[
      if (state.listError != null) ...[
        MessageBanner(
          message: state.listError!,
          actionLabel: StaffCopy.retry,
          onAction: onRefresh,
        ),
        const SizedBox(height: Gaps.lg),
      ],
      if (items == null)
        for (var i = 0; i < 3; i++) const _SkeletonRow()
      else if (items.isEmpty && state.listError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gaps.xxxl),
          child: Text(
            StaffCopy.empty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        )
      else
        for (final item in items)
          _QueueRow(item: item, now: now ?? DateTime.now(), onTap: () => onOpen(item)),
    ];
    // Always scrollable, so pull-to-refresh works on an empty list too.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gaps.lg),
      children: children,
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, required this.now, required this.onTap});

  final EnrolmentItem item;
  final DateTime now;
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
                      Text(StaffCopy.phone(item.phone), style: theme.textTheme.titleMedium),
                      const SizedBox(height: Gaps.xs),
                      Text(
                        '${StaffCopy.role(item.role)} · ${StaffCopy.age(item.createdAt, now)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (item.flags.isNotEmpty) ...[
                  const SizedBox(width: Gaps.sm),
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    semanticLabel: StaffCopy.flagged,
                  ),
                ],
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

/// A grey block shaped like a row, shown while the list loads.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: Gaps.sm),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
