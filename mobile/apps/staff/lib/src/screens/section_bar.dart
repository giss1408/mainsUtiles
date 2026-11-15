import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';

/// The queues this staff member may work, in the order of the bar.
List<StaffSection> sectionsFor(StaffMe me) => [
      if (me.can('review_enrolment')) StaffSection.enrolments,
      if (me.can('send_contact_code')) StaffSection.contacts,
      if (me.can('verify_payment') || me.can('make_refund')) StaffSection.payments,
      if (me.can('send_message')) StaffSection.messages,
      if (me.can('make_payout') || me.can('resolve_dispute')) StaffSection.jobs,
    ];

/// Makes the counts of what waits available to the section bar of every queue screen.
class AlertsScope extends InheritedWidget {
  const AlertsScope({super.key, required this.alerts, required super.child});

  final StaffAlerts? alerts;

  static StaffAlerts? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AlertsScope>()?.alerts;

  @override
  bool updateShouldNotify(AlertsScope oldWidget) => oldWidget.alerts != alerts;
}

/// Switches between the queues. One destination per right the staff member holds; nothing
/// when they hold only one. A badge counts what waits; it turns red when something is late.
Widget? sectionBar({
  required StaffMe? me,
  required StaffSection section,
  required ValueChanged<StaffSection>? onSection,
}) {
  if (me == null || onSection == null) return null;
  final sections = sectionsFor(me);
  if (sections.length < 2) return null;
  const labels = {
    StaffSection.enrolments: (Icons.phone_android_outlined, StaffCopy.enrolmentsTitle),
    StaffSection.contacts: (Icons.people_outline, StaffCopy.contactsTitle),
    StaffSection.payments: (Icons.payments_outlined, StaffCopy.paymentsTitle),
    StaffSection.messages: (Icons.chat_outlined, StaffCopy.messagesTitle),
    StaffSection.jobs: (Icons.work_outline, StaffCopy.jobsTitle),
  };
  return Builder(
    builder: (context) {
      final alerts = AlertsScope.of(context);
      (int, bool) waiting(StaffSection entry) => switch (entry) {
            StaffSection.payments => (alerts?.payments ?? 0, alerts?.paymentsLate ?? false),
            StaffSection.messages => (alerts?.messages ?? 0, alerts?.messagesLate ?? false),
            StaffSection.jobs => (alerts?.jobs ?? 0, alerts?.jobsLate ?? false),
            _ => (0, false),
          };
      return NavigationBar(
        selectedIndex: sections.indexOf(section).clamp(0, sections.length - 1),
        onDestinationSelected: (i) => onSection(sections[i]),
        labelBehavior: sections.length > 3
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final entry in sections)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: waiting(entry).$1 > 0,
                label: Text('${waiting(entry).$1}'),
                backgroundColor: waiting(entry).$2 ? AppColors.danger : AppColors.primary,
                child: Icon(labels[entry]!.$1),
              ),
              label: labels[entry]!.$2,
              tooltip: waiting(entry).$1 > 0
                  ? StaffCopy.waiting(labels[entry]!.$2, waiting(entry).$1, late: waiting(entry).$2)
                  : labels[entry]!.$2,
            ),
        ],
      );
    },
  );
}
