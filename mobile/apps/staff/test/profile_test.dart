import 'package:flutter_test/flutter_test.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_copy.dart';

import 'screens_test.dart';

void main() {
  testWidgets('the account icon opens the profile with the username', (tester) async {
    await pumpSignedIn(tester);
    await tester.tap(find.byTooltip(StaffCopy.profileTitle));
    await settle(tester);
    expect(find.text(StaffCopy.profileTitle), findsWidgets);
    expect(find.text('agent'), findsOneWidget);
    expect(find.text(StaffCopy.permissionsLabel), findsOneWidget);
  });

  testWidgets('sign out from the profile returns to the login screen', (tester) async {
    final screen = await pumpSignedIn(tester);
    await tester.tap(find.byTooltip(StaffCopy.profileTitle));
    await settle(tester);
    await tester.tap(find.text(StaffCopy.signOut));
    await settle(tester);
    expect(find.text(StaffCopy.loginTitle), findsWidgets);
    expect(screen.controller.state.stage, StaffStage.login);
  });
}
