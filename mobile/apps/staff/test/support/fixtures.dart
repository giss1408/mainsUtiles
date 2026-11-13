import 'package:petitgombo_core/petitgombo_core.dart';
import 'package:staff/src/staff_api.dart';
import 'package:staff/src/staff_controller.dart';
import 'package:staff/src/staff_session.dart';

import 'fake_adapter.dart';

Map<String, dynamic> itemJson({
  String id = 'a1',
  String status = 'pending',
  List<String> flags = const [],
  String? reason,
}) =>
    {
      'id': id,
      'phone': '+2250708091011',
      'role': 'jobber',
      'kind': 'new_account',
      'status': status,
      'flags': flags,
      'device_model': 'Tecno Spark',
      'platform': 'android',
      'integrity_verdict': 'unchecked',
      'created_at': '2026-11-12T10:00:00Z',
      if (reason != null) 'reason': reason,
    };

EnrolmentItem item({String id = 'a1', String status = 'pending', List<String> flags = const []}) =>
    EnrolmentItem.fromJson(itemJson(id: id, status: status, flags: flags));

const allPermissions = ['review_enrolment', 'send_enrolment_code'];

/// A store whose contents tests can inspect.
class RecordingStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A session that is already signed in, for screen tests.
class SignedInSession extends StaffSession {
  SignedInSession(StaffApi api)
      : super(api, DeviceIdentity(InMemoryKeyValueStore()),
            deviceModel: 'Test', platform: 'android');

  bool signedOut = false;

  @override
  String? get access => signedOut ? null : 'acc';

  @override
  Future<bool> refresh() async => false;

  @override
  void signOut() => signedOut = true;
}

class Harness {
  Harness() {
    api = StaffApi(dioWith(adapter));
    session =
        StaffSession(api, DeviceIdentity(store), deviceModel: 'Samsung A15', platform: 'android');
    controller = StaffController(api: api, session: session);
  }

  final adapter = FakeAdapter();
  final store = RecordingStore();
  late final StaffApi api;
  late final StaffSession session;
  late final StaffController controller;

  /// Queues the replies of a complete sign-in on an activated phone.
  void queueSignIn(
      {List<Map<String, dynamic>> pending = const [], List<String> permissions = allPermissions}) {
    adapter
      ..reply(200, {'status': 'active'})
      ..reply(200, {'nonce': 'n1'})
      ..reply(200, {'access': 'acc', 'refresh': 'ref'})
      ..reply(200, {'id': 'u1', 'username': 'agent', 'permissions': permissions})
      ..reply(200, {'count': pending.length, 'next': null, 'previous': null, 'results': pending});
  }
}

Map<String, dynamic> contactJson({
  String id = 'c1',
  String action = 'send',
  String relationship = 'parent',
  String? name,
  String? jobberName,
}) =>
    {
      'id': id,
      'relationship': relationship,
      'action': action,
      'created_at': '2026-11-12T10:00:00Z',
      if (name != null) 'name': name,
      if (name != null) 'jobber_name': jobberName,
    };

Map<String, dynamic> page(List<Map<String, dynamic>> rows) =>
    {'count': rows.length, 'next': null, 'previous': null, 'results': rows};

const contactPermissions = ['send_contact_code'];

Map<String, dynamic> paymentJson({
  String id = 'p1',
  String action = 'check',
  bool late = false,
  bool detail = false,
}) =>
    {
      'id': id,
      'category_name': 'Ménage',
      'starts_at': '2026-11-14T08:00:00Z',
      'amount_xof': 3500,
      'method_label': 'Wave',
      'submitted_at': '2026-11-13T10:00:00Z',
      'late': late,
      'action': action,
      if (detail) ...{
        'fee_xof': 0,
        'reference': 'WAVE-123456',
        'method_number': '+2250101010101',
        'seen_before': false,
        'status': action == 'refund' ? 'refund_due' : 'submitted',
      },
    };

const paymentPermissions = ['verify_payment', 'make_refund'];
