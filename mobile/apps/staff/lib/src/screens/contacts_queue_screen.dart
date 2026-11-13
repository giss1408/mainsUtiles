import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;
import 'section_bar.dart';
import 'staff_profile_screen.dart';

/// The trusted contacts staff have to send a code to, or to warn. No name and no number
/// are listed: they appear on the detail screen only.
class ContactsQueueScreen extends StatelessWidget {
  const ContactsQueueScreen({
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
  final ValueChanged<ContactItem> onOpen;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final initial = StaffCopy.contactTabs.indexWhere((t) => t.$1 == state.contactTab);
    return DefaultTabController(
      length: StaffCopy.contactTabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(StaffCopy.contactsTitle),
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
            onTap: (index) => onTab(StaffCopy.contactTabs[index].$1),
            tabs: [for (final tab in StaffCopy.contactTabs) Tab(text: tab.$2)],
          ),
        ),
        bottomNavigationBar:
            sectionBar(me: state.me, section: StaffSection.contacts, onSection: onSection),
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
    final rows = state.contacts;
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
            StaffCopy.contactsEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        )
      else
        for (final row in rows)
          _Row(item: row, now: now ?? DateTime.now(), onTap: () => onOpen(row)),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gaps.lg),
      children: children,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.now, required this.onTap});

  final ContactItem item;
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
                      Text(
                        StaffCopy.contactRelationship(item.relationship),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: Gaps.xs),
                      Text(
                        '${StaffCopy.contactAction(item.action)} · ${StaffCopy.age(item.createdAt, now)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
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
      height: 72,
      margin: const EdgeInsets.only(bottom: Gaps.sm),
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.4),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    );
  }
}
