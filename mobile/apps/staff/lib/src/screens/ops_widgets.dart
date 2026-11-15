import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';
import 'queue_screen.dart' show maxContentWidth;
import 'section_bar.dart';
import 'staff_profile_screen.dart';

/// The frame of a queue: title, profile button, optional tabs, the section bar, pull to refresh.
class OpsQueueScaffold extends StatelessWidget {
  const OpsQueueScaffold({
    super.key,
    required this.title,
    required this.section,
    required this.me,
    required this.onRefresh,
    required this.onSignOut,
    required this.children,
    this.onSection,
    this.tabs = const [],
    this.tab,
    this.onTab,
  });

  final String title;
  final StaffSection section;
  final StaffMe? me;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final ValueChanged<StaffSection>? onSection;
  final List<Widget> children;

  /// `(value, label)`; the tab bar is shown from two tabs on.
  final List<(String, String)> tabs;
  final String? tab;
  final ValueChanged<String>? onTab;

  @override
  Widget build(BuildContext context) {
    final initial = tabs.indexWhere((t) => t.$1 == tab);
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: StaffCopy.profileTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StaffProfileScreen(me: me, onSignOut: onSignOut),
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
        bottom: tabs.length < 2
            ? null
            : TabBar(
                onTap: (index) => onTab?.call(tabs[index].$1),
                tabs: [for (final entry in tabs) Tab(text: entry.$2)],
              ),
      ),
      bottomNavigationBar: sectionBar(me: me, section: section, onSection: onSection),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Gaps.lg),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
    if (tabs.length < 2) return scaffold;
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: scaffold,
    );
  }
}

/// The body of a queue: the error with a retry, a skeleton while loading, the empty state, the rows.
List<Widget> queueBody<T>(
  BuildContext context, {
  required List<T>? rows,
  required String? listError,
  required String empty,
  required Future<void> Function() onRefresh,
  required Widget Function(T row) row,
}) =>
    [
      if (listError != null) ...[
        MessageBanner(message: listError, actionLabel: StaffCopy.retry, onAction: onRefresh),
        const SizedBox(height: Gaps.lg),
      ],
      if (rows == null)
        for (var i = 0; i < 3; i++) const QueueSkeleton()
      else if (rows.isEmpty && listError == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gaps.xxxl),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        )
      else
        for (final item in rows) row(item),
    ];

/// One line of a queue: a title, muted lines, marker pills, a chevron.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.title,
    required this.lines,
    required this.onTap,
    this.pills = const [],
  });

  final String title;
  final List<String> lines;
  final List<Widget> pills;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted);
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
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: Gaps.xs),
                      for (final line in lines) Text(line, style: muted),
                      if (pills.isNotEmpty) ...[
                        const SizedBox(height: Gaps.sm),
                        Wrap(spacing: Gaps.sm, runSpacing: Gaps.xs, children: pills),
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

const latePill = StatusPill(icon: Icons.warning_amber_rounded, label: StaffCopy.late);

class QueueSkeleton extends StatelessWidget {
  const QueueSkeleton({super.key});

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

/// The frame of a detail: a back arrow that closes it (and drops what it showed), the error banner.
class OpsDetailScaffold extends StatelessWidget {
  const OpsDetailScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
    this.error,
  });

  final String title;
  final VoidCallback onBack;
  final String? error;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: StaffCopy.back,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(title),
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
                    if (error != null) ...[
                      MessageBanner(message: error!),
                      const SizedBox(height: Gaps.lg),
                    ],
                    ...children,
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

class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});

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
