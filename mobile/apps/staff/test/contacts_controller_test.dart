import 'package:flutter_test/flutter_test.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_copy.dart';

import 'support/fixtures.dart';

Future<Harness> signedIn({List<String> permissions = allPermissions}) async {
  final h = Harness();
  h.queueSignIn(permissions: permissions);
  await h.controller.signIn('agent', 'pw');
  return h;
}

void main() {
  test('a contact agent lands on the contacts section and loads its queue', () async {
    final h = Harness();
    h.adapter
      ..reply(200, {'status': 'active'})
      ..reply(200, {'nonce': 'n1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(200, {'id': 'u1', 'username': 'agent', 'permissions': contactPermissions})
      ..reply(200, page([contactJson()]));
    await h.controller.signIn('agent', 'pw');

    expect(h.controller.state.section, StaffSection.contacts);
    expect(h.controller.state.contacts!.single.id, 'c1');
    final last = h.adapter.requests.last;
    expect(last.path, '/api/v1/staff/contacts');
    expect(last.queryParameters['file'], 'send');
  });

  test('an agent with both rights starts on enrolments and can switch', () async {
    final h = await signedIn(permissions: [...allPermissions, ...contactPermissions]);
    expect(h.controller.state.section, StaffSection.enrolments);

    h.adapter.reply(200, page([contactJson(id: 'c2')]));
    await h.controller.selectSection(StaffSection.contacts);
    expect(h.controller.state.section, StaffSection.contacts);
    expect(h.controller.state.contacts!.single.id, 'c2');
  });

  test('the notice tab asks for the notice queue', () async {
    final h = await signedIn(permissions: contactPermissions);
    h.adapter.reply(200, page([contactJson(id: 'c3', action: 'notice')]));
    await h.controller.selectContactTab('notice');
    expect(h.adapter.requests.last.queryParameters['file'], 'notice');
    expect(h.controller.state.contacts!.single.action, 'notice');
  });

  test('opening a contact loads its name, and sending hands back the link and drops the row',
      () async {
    final h = await signedIn(permissions: contactPermissions);
    h.adapter.reply(200, page([contactJson()]));
    await h.controller.refreshContacts();
    h.adapter.reply(200, contactJson(name: 'Awa Koné', jobberName: 'Koffi Yao'));
    await h.controller.openContact(h.controller.state.contacts!.single);
    expect(h.controller.state.contactSelected!.name, 'Awa Koné');
    expect(h.controller.state.contactSelected!.jobberName, 'Koffi Yao');

    h.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250101010101?text=code%20%3A%20123456'});
    final uri = await h.controller.sendContact();
    expect(uri.toString(), contains('wa.me/2250101010101'));
    expect(h.adapter.requests.last.path, '/api/v1/staff/contacts/c1/send');
    expect(h.controller.state.contacts, isEmpty);
    // The link carries the code: it is not kept anywhere in the state.
    expect(h.controller.state.toString(), isNot(contains('123456')));
    expect(h.store.values.values.join(), isNot(contains('123456')));
  });

  test('a notice goes to the notice endpoint', () async {
    final h = await signedIn(permissions: contactPermissions);
    h.adapter.reply(200, page([contactJson(action: 'notice')]));
    await h.controller.selectContactTab('notice');
    h.adapter.reply(200, contactJson(action: 'notice', name: 'Vieux', jobberName: null));
    await h.controller.openContact(h.controller.state.contacts!.single);
    h.adapter.reply(200, {'whatsapp_url': 'https://wa.me/2250101010101?text=x'});
    expect(await h.controller.noticeContact(), isNotNull);
    expect(h.adapter.requests.last.path, '/api/v1/staff/contacts/c1/notice');
    expect(h.controller.state.contacts, isEmpty);
  });

  test('a refused send shows the server message and keeps the row', () async {
    final h = await signedIn(permissions: contactPermissions);
    h.adapter.reply(200, page([contactJson()]));
    await h.controller.refreshContacts();
    h.adapter.reply(200, contactJson(name: 'Awa', jobberName: null));
    await h.controller.openContact(h.controller.state.contacts!.single);
    h.adapter.reply(409, {'error': 'invalid_state', 'message': 'Action impossible maintenant.'});
    expect(await h.controller.sendContact(), isNull);
    expect(h.controller.state.error, 'Action impossible maintenant.');
    expect(h.controller.state.contacts, hasLength(1));
    expect(h.controller.state.busy, isFalse);
  });

  test('copy names the section and the actions in French', () {
    expect(StaffCopy.contactsTitle, 'Personnes de confiance');
    expect(StaffCopy.contactRelationship('friend'), 'Ami(e)');
    expect(StaffCopy.permission('send_contact_code'), isNot('send_contact_code'));
  });
}
