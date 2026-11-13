import 'package:flutter/material.dart';

import '../staff_controller.dart';
import '../staff_copy.dart';
import '../staff_api.dart';

/// Switches between the enrolment queue and the trusted contacts queue. Shown only to
/// an agent who may work both.
Widget? sectionBar({
  required StaffMe? me,
  required StaffSection section,
  required ValueChanged<StaffSection>? onSection,
}) {
  if (me == null || onSection == null) return null;
  if (!(me.can('review_enrolment') && me.can('send_contact_code'))) return null;
  return NavigationBar(
    selectedIndex: section.index,
    onDestinationSelected: (i) => onSection(StaffSection.values[i]),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.phone_android_outlined),
        label: StaffCopy.enrolmentsTitle,
      ),
      NavigationDestination(
        icon: Icon(Icons.people_outline),
        label: StaffCopy.contactsTitle,
      ),
    ],
  );
}
