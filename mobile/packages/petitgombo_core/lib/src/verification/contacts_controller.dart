import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../auth/session.dart';
import '../app/providers.dart';
import '../enrolment/phone_format.dart';
import 'verification_api.dart';
import 'verification_controller.dart';
import 'verification_copy.dart';
import 'verification_models.dart';

const _keep = Object();

class ContactsState {
  const ContactsState({
    this.contacts,
    this.max = 2,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<TrustedContact>? contacts;
  final int max;
  final bool loading;
  final bool sending;

  /// A French message for the current screen.
  final String? error;

  ContactsState copyWith({
    List<TrustedContact>? contacts,
    int? max,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      ContactsState(
        contacts: contacts ?? this.contacts,
        max: max ?? this.max,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The jobber's trusted contacts: add, ask for a code, confirm it, replace. Never delete.
class ContactsController extends StateNotifier<ContactsState> {
  ContactsController({
    required VerificationApi api,
    required Session session,
    required Future<void> Function() refreshChecklist,
  })  : _api = api,
        _session = session,
        _refreshChecklist = refreshChecklist,
        super(const ContactsState());

  final VerificationApi _api;
  final Session _session;
  final Future<void> Function() _refreshChecklist;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await _session.authorized(_api.contacts);
      state = state.copyWith(contacts: result.contacts, max: result.max, loading: false);
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  void clearError() => state = state.copyWith(error: null);

  Future<TrustedContact?> add({
    required String name,
    required String phone,
    required String relationship,
  }) =>
      _change(
        phone,
        (access, number) =>
            _api.addContact(access, name: name, phone: number, relationship: relationship),
      );

  Future<TrustedContact?> replace(
    String id, {
    required String name,
    required String phone,
    required String relationship,
  }) =>
      _change(
        phone,
        (access, number) =>
            _api.replaceContact(access, id, name: name, phone: number, relationship: relationship),
      );

  /// Asks staff for a (new) code.
  Future<bool> requestCode(String id) async =>
      await _run((access) => _api.requestContactCode(access, id)) != null;

  Future<bool> confirm(String id, String code) async {
    final contact = await _run((access) => _api.confirmContact(access, id, code.trim()));
    if (contact == null) return false;
    await _refreshChecklist();
    return true;
  }

  Future<TrustedContact?> _change(
    String phone,
    Future<TrustedContact> Function(String access, String number) call,
  ) async {
    final number = normaliseIvorianPhone(phone);
    if (number == null) {
      state = state.copyWith(error: VerificationCopy.contactPhoneInvalid);
      return null;
    }
    final contact = await _run((access) => call(access, number));
    if (contact != null) await _refreshChecklist();
    return contact;
  }

  /// One call, then the list is read again so the screen shows what the server holds.
  Future<TrustedContact?> _run(Future<TrustedContact> Function(String access) call) async {
    if (state.sending) return null;
    state = state.copyWith(sending: true, error: null);
    try {
      final contact = await _session.authorized(call);
      state = state.copyWith(sending: false);
      await _reload();
      return contact;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: _message(e));
      return null;
    }
  }

  Future<void> _reload() async {
    try {
      final result = await _session.authorized(_api.contacts);
      state = state.copyWith(contacts: result.contacts, max: result.max);
    } on ApiError {
      // The change went through; the list is refreshed on the next visit.
    }
  }

  String _message(ApiError e) {
    if (e.isNetwork) return VerificationCopy.offline;
    if (e.status == 401) return VerificationCopy.sessionExpired;
    return e.message.isNotEmpty ? e.message : VerificationCopy.genericError;
  }
}

final contactsControllerProvider = StateNotifierProvider<ContactsController, ContactsState>(
  (ref) => ContactsController(
    api: ref.watch(verificationApiProvider),
    session: ref.watch(sessionProvider),
    refreshChecklist: () => ref.read(verificationControllerProvider.notifier).load(),
  ),
);
