import 'package:flutter/material.dart';

import '../staff_api.dart';
import '../staff_controller.dart';
import '../staff_copy.dart';

/// The queues this staff member may work, in the order of the bar.
List<StaffSection> sectionsFor(StaffMe me) => [
      if (me.can('review_enrolment')) StaffSection.enrolments,
      if (me.can('send_contact_code')) StaffSection.contacts,
      if (me.can('verify_payment') || me.can('make_refund')) StaffSection.payments,
    ];

/// Switches between the queues. One destination per right the staff member holds; nothing
/// when they hold only one.
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
  };
  return NavigationBar(
    selectedIndex: sections.indexOf(section).clamp(0, sections.length - 1),
    onDestinationSelected: (i) => onSection(sections[i]),
    destinations: [
      for (final entry in sections)
        NavigationDestination(icon: Icon(labels[entry]!.$1), label: labels[entry]!.$2),
    ],
  );
}
