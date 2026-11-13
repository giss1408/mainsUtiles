// Tests read the notifier state directly.
// ignore_for_file: invalid_use_of_protected_member
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

const _jobberBase = '/api/v1/jobber/verification';

void main() {
  late FakeAdapter adapter;

  setUp(() => adapter = FakeAdapter());

  test('a jobber checklist parses identity, guarantor and the tier', () async {
    adapter.reply(
      200,
      jobberChecklistJson(
        tier: 'J1',
        identity: {'status': 'confirmed', 'reason': ''},
        guarantor: {'status': 'refused', 'reason': 'Facture illisible.'},
      ),
    );
    final api = VerificationApi(dioWith(adapter), base: _jobberBase);
    final checklist = await api.checklist('acc');
    expect(adapter.requests.single.path, _jobberBase);
    expect(checklist.forJobber, isTrue);
    expect(checklist.verified, isTrue);
    expect(checklist.identity.status, StepStatus.confirmed);
    expect(checklist.guarantor.status, StepStatus.refused);
    expect(checklist.guarantor.reason, 'Facture illisible.');
  });

  test('a householder checklist is unchanged and has no guarantor step', () {
    final checklist = VerificationChecklist.fromJson(checklistJson(tier: 'H1'));
    expect(checklist.forJobber, isFalse);
    expect(checklist.verified, isTrue);
    expect(checklist.guarantor.status, StepStatus.notStarted);
    expect(VerificationChecklist.fromJson(jobberChecklistJson()).verified, isFalse);
  });

  test('submitGuarantor posts multipart to the jobber base', () async {
    adapter.reply(201, jobberChecklistJson(guarantor: {'status': 'submitted', 'reason': ''}));
    final api = VerificationApi(dioWith(adapter), base: _jobberBase);
    final checklist = await api.submitGuarantor(
      'acc',
      documentType: 'facture_eau',
      photo: photo(7),
      guarantorName: 'Kouassi Yao',
      guarantorPhone: '+2250707070707',
      relationship: 'parent',
    );
    expect(checklist.guarantor.status, StepStatus.submitted);
    final request = adapter.requests.single;
    expect(request.path, '$_jobberBase/guarantor');
    expect(request.headers['Authorization'], 'Bearer acc');
    final form = request.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['document_type'], 'facture_eau');
    expect(fields['guarantor_name'], 'Kouassi Yao');
    expect(fields['guarantor_phone'], '+2250707070707');
    expect(fields['relationship'], 'parent');
    expect(fields.containsKey('captured_at'), isTrue);
    expect(form.files.single.key, 'photo');
    expect(request.sendTimeout, const Duration(minutes: 2));
  });

  test('the provider uses the jobber base only for the jobber role', () async {
    for (final (role, path) in [
      (AppRole.jobber, _jobberBase),
      (AppRole.householder, '/api/v1/verification'),
    ]) {
      final adapter = FakeAdapter()
        ..reply(200, role == AppRole.jobber ? jobberChecklistJson() : checklistJson());
      final container = ProviderContainer(
        overrides: [
          appRoleProvider.overrideWithValue(role),
          dioProvider.overrideWithValue(dioWith(adapter)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(verificationApiProvider).checklist('acc');
      expect(adapter.requests.single.path, path);
    }
  });

  group('controller', () {
    late VerificationController controller;

    setUp(() async {
      final store = InMemoryKeyValueStore();
      final dio = dioWith(adapter);
      final session = Session(ApiClient(dio), DeviceIdentity(store), store);
      adapter
        ..reply(200, {'nonce': 'n-1'})
        ..reply(200, {'access': 'acc', 'refresh': 'ref'})
        ..reply(200, {'id': 'u-1', 'phone': '+2250505050505', 'role': 'jobber', 'device_id': 'd'});
      await session.signIn();
      adapter.requests.clear();
      controller = VerificationController(
        api: VerificationApi(dio, base: _jobberBase),
        session: session,
        position: FakePositionReader(),
      );
    });

    Future<bool> send(String phone) => controller.sendGuarantor(
          documentType: 'facture_eau',
          photo: photo(1),
          guarantorName: 'Kouassi Yao',
          guarantorPhone: phone,
          relationship: 'parent',
        );

    test('sendGuarantor sends the normalised phone and stores the checklist', () async {
      adapter.reply(201, jobberChecklistJson(guarantor: {'status': 'submitted', 'reason': ''}));
      expect(await send('07 07 07 07 07'), isTrue);
      final form = adapter.requests.single.data as FormData;
      expect(Map.fromEntries(form.fields)['guarantor_phone'], '+2250707070707');
      expect(controller.state.checklist!.guarantor.status, StepStatus.submitted);
    });

    test('an invalid phone is refused without a request', () async {
      expect(await send('12345'), isFalse);
      expect(adapter.requests, isEmpty);
      expect(controller.state.error, VerificationCopy.guarantorPhoneInvalid);
    });

    test('409 invalid_state means it was already sent', () async {
      adapter
        ..reply(409, {'error': 'invalid_state', 'message': 'Cette étape est déjà envoyée.'})
        ..reply(200, jobberChecklistJson(guarantor: {'status': 'submitted', 'reason': ''}));
      expect(await send('0707070707'), isTrue);
      expect(adapter.requests.last.path, _jobberBase);
      expect(controller.state.checklist!.guarantor.status, StepStatus.submitted);
    });

    test('offline keeps the photo message', () async {
      adapter.offline = true;
      expect(await send('0707070707'), isFalse);
      expect(controller.state.error, VerificationCopy.offlinePhotosKept);
    });
  });
}
