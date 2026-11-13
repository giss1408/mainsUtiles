import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_copy.dart';

/// The signed-in staff member: who they are, what they may do, and sign-out.
class StaffProfileScreen extends StatelessWidget {
  const StaffProfileScreen({super.key, required this.me, required this.onSignOut});

  final StaffMe? me;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = me?.permissions ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text(StaffCopy.profileTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(Gaps.lg),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      const IconTile(icon: Icons.badge_outlined),
                      const SizedBox(width: Gaps.md),
                      Expanded(
                        child: Text(me?.username ?? '', style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(StaffCopy.permissionsLabel),
                AppCard(
                  child: permissions.isEmpty
                      ? Text(StaffCopy.noPermissions, style: theme.textTheme.bodyLarge)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final permission in permissions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: Gaps.sm),
                                child: MetaChip(
                                  icon: Icons.check_circle_outline,
                                  label: StaffCopy.permission(permission),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: Gaps.xl),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    onSignOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text(StaffCopy.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
