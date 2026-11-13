import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff/main.dart';
import 'package:staff/src/providers.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';

import 'support/fake_adapter.dart';
import 'support/fixtures.dart';

class Screen {
  final adapter = FakeAdapter();
  final opened = <Uri>[];
  bool whatsAppInstalled = true;
  late final StaffController controller;
}

Future<Screen> pump(
  WidgetTester tester, {
  List<ContactItem> rows = const [],
  ContactItem? selected,
  List<String> permissions = contactPermissions,
  StaffSection section = StaffSection.contacts,
}) async {
  final screen = Screen();
  final api = StaffApi(dioWith(screen.adapter));
  screen.controller = StaffController(
    api: api,
    session: SignedInSession(api),
    initial: StaffState(
      stage: StaffStage.queue,
      me: StaffMe(id: 'u1', username: 'agent', permissions: permissions),
      section: section,
      contacts: rows,
      contactSelected: selected,
      items: const [],
    ),
  );
  await tester.pumpWidget(
    buildApp(
      overrides: [
        staffControllerProvider.overrideWith((ref) => screen.controller),
        urlOpenerProvider.overrideWithValue((uri) async {
          screen.opened.add(uri);
          return screen.whatsAppInstalled;
        }),
      ],
    ),
  );
  await tester.pump();
  return screen;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ContactItem row({String action = 'send', String? name, String? jobberName}) => ContactItem.fromJson(
    contactJson(action: action, relationship: 'friend', name: name, jobberName: jobberName));

void main() {
  testWidgets('the queue lists the relationship and the action, never a name or a number',
      (tester) async {
    await pump(tester, rows: [row()]);
    expect(find.text('Personnes de confiance'), findsWidgets);
    expect(find.text('Ami(e)'), findsOneWidget);
    expect(find.textContaining('Code à envoyer'), findsOneWidget);
    expect(find.textContaining('+225'), findsNothing);
  });

  testWidgets('an empty queue says so', (tester) async {
    await pump(tester);
    expect(find.text('Aucune personne de confiance à traiter.'), findsOneWidget);
  });

  testWidgets('the section bar shows only to an agent with both rights', (tester) async {
    await pump(tester);
    expect(find.text('Enrôlements'), findsNothing);
  });

  testWidgets('both rights: the bar switches to the enrolments queue', (tester) async {
    final screen = await pump(tester, permissions: [...allPermissions, ...contactPermissions]);
    expect(find.text('Enrôlements'), findsOneWidget);
    screen.adapter.reply(200, {'count': 0, 'next': null, 'previous': null, 'results': []});
    await tester.tap(find.text('Enrôlements'));
    await settle(tester);
    expect(screen.controller.state.section, StaffSection.enrolments);
    expect(find.text("Demandes d'enrôlement"), findsOneWidget);
  });

  testWidgets('send opens WhatsApp with the link and warns not to copy the code', (tester) async {
    final screen =
        await pump(tester, rows: [row()], selected: row(name: 'Awa Koné', jobberName: 'Koffi Yao'));
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(find.text('Koffi Yao'), findsOneWidget);
    expect(find.textContaining('Ne recopiez pas ce code'), findsOneWidget);
    screen.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250101010101?text=code'});
    await tester.tap(find.text('Envoyer le code par WhatsApp'));
    await settle(tester);
    expect(screen.opened.single.toString(), 'https://wa.me/2250101010101?text=code');
    expect(find.textContaining('0101010101'), findsNothing);
  });

  testWidgets('notice shows its own button and note', (tester) async {
    final screen = await pump(tester,
        rows: [row(action: 'notice')], selected: row(action: 'notice', name: 'Vieux'));
    expect(find.text("Prévenir l'ancienne personne par WhatsApp"), findsOneWidget);
    expect(find.textContaining('quelques jours'), findsOneWidget);
    screen.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250101010101?text=x'});
    await tester.tap(find.text("Prévenir l'ancienne personne par WhatsApp"));
    await settle(tester);
    expect(screen.opened, hasLength(1));
    expect(screen.adapter.requests.last.path, '/api/v1/staff/contacts/c1/notice');
  });

  testWidgets('without WhatsApp installed the agent is told', (tester) async {
    final screen = await pump(tester, rows: [row()], selected: row(name: 'Awa'));
    screen.whatsAppInstalled = false;
    screen.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250101010101?text=c'});
    await tester.tap(find.text('Envoyer le code par WhatsApp'));
    await settle(tester);
    expect(find.text("WhatsApp n'est pas installé sur cet appareil."), findsOneWidget);
  });

  testWidgets('the screens fit 320dp at double text size', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await pump(tester, rows: [row()], permissions: [...allPermissions, ...contactPermissions]);
    expect(tester.takeException(), isNull);
    final screen = await pump(tester,
        rows: [row()], selected: row(name: 'Awa Koné Kouassi', jobberName: 'Koffi Yao'));
    expect(screen.controller.state.contactSelected, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
