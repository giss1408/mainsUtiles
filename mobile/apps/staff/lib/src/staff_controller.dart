import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'staff_api.dart';
import 'staff_copy.dart';
import 'staff_session.dart';

enum StaffStage { login, devicePending, queue }

/// Which queue the agent is working.
enum StaffSection { enrolments, contacts }

const _keep = Object();

class StaffState {
  const StaffState({
    this.stage = StaffStage.login,
    this.busy = false,
    this.error,
    this.me,
    this.tab = 'pending',
    this.items,
    this.listError,
    this.selected,
    this.section = StaffSection.enrolments,
    this.contactTab = 'send',
    this.contacts,
    this.contactSelected,
  });

  final StaffStage stage;

  /// A sign-in or an action is in progress.
  final bool busy;

  /// A message for the current screen (login or detail).
  final String? error;
  final StaffMe? me;

  /// The status shown in the queue.
  final String tab;

  /// The queue; null while it loads.
  final List<EnrolmentItem>? items;
  final String? listError;

  /// The application open in the detail screen.
  final EnrolmentItem? selected;

  final StaffSection section;

  /// `send` or `notice`.
  final String contactTab;

  /// The trusted contacts queue; null while it loads.
  final List<ContactItem>? contacts;
  final ContactItem? contactSelected;

  StaffState copyWith({
    bool? busy,
    Object? error = _keep,
    String? tab,
    Object? items = _keep,
    Object? listError = _keep,
    Object? selected = _keep,
    StaffSection? section,
    String? contactTab,
    Object? contacts = _keep,
    Object? contactSelected = _keep,
  }) =>
      StaffState(
        stage: stage,
        section: section ?? this.section,
        contactTab: contactTab ?? this.contactTab,
        contacts: identical(contacts, _keep) ? this.contacts : contacts as List<ContactItem>?,
        contactSelected: identical(contactSelected, _keep)
            ? this.contactSelected
            : contactSelected as ContactItem?,
        busy: busy ?? this.busy,
        error: identical(error, _keep) ? this.error : error as String?,
        me: me,
        tab: tab ?? this.tab,
        items: identical(items, _keep) ? this.items : items as List<EnrolmentItem>?,
        listError: identical(listError, _keep) ? this.listError : listError as String?,
        selected: identical(selected, _keep) ? this.selected : selected as EnrolmentItem?,
      );
}

/// Drives the staff app: sign-in, the queue and the actions on one application.
class StaffController extends StateNotifier<StaffState> {
  StaffController({required StaffApi api, required StaffSession session, StaffState? initial})
      : _api = api,
        _session = session,
        super(initial ?? const StaffState());

  final StaffApi _api;
  final StaffSession _session;

  Future<void> signIn(String username, String password) async {
    if (state.busy) return;
    state = const StaffState(busy: true);
    try {
      final me = await _session.signIn(username, password);
      // An agent who may only send contact codes starts on that queue.
      final contactsOnly = !me.can('review_enrolment') && me.can('send_contact_code');
      state = StaffState(
        stage: StaffStage.queue,
        me: me,
        section: contactsOnly ? StaffSection.contacts : StaffSection.enrolments,
      );
    } on ApiError catch (e) {
      state = e.code == 'device_pending'
          ? const StaffState(stage: StaffStage.devicePending)
          : StaffState(error: StaffCopy.loginError(e));
      return;
    }
    await (state.section == StaffSection.contacts ? refreshContacts() : refresh());
  }

  /// Back to the login screen, where the password is typed again.
  void signOut({String? message}) {
    _session.signOut();
    state = StaffState(error: message);
  }

  Future<void> selectSection(StaffSection section) async {
    if (state.stage != StaffStage.queue || section == state.section) return;
    state = state.copyWith(section: section, error: null);
    if (section == StaffSection.contacts) {
      state = state.copyWith(contacts: null, listError: null);
      await refreshContacts();
    } else {
      state = state.copyWith(items: null, listError: null);
      await refresh();
    }
  }

  Future<void> selectContactTab(String file) async {
    if (state.stage != StaffStage.queue || file == state.contactTab) return;
    state = state.copyWith(contactTab: file, contacts: null, listError: null);
    await refreshContacts();
  }

  Future<void> refreshContacts() async {
    final tab = state.contactTab;
    final rows = await _guard((access) => _api.contacts(access, file: tab), onError: (message) {
      if (state.contactTab == tab) {
        state = state.copyWith(contacts: state.contacts ?? const [], listError: message);
      }
    });
    if (rows != null && state.stage == StaffStage.queue && state.contactTab == tab) {
      state = state.copyWith(contacts: rows, listError: null);
    }
  }

  /// Opens a contact and loads the names the list does not carry (the server audits it).
  Future<void> openContact(ContactItem item) async {
    state = state.copyWith(contactSelected: item, error: null);
    final detail = await _guard((access) => _api.contact(access, item.id), onError: (_) {});
    if (detail != null && state.contactSelected?.id == item.id) {
      state = state.copyWith(contactSelected: detail);
    }
  }

  void closeContact() => state = state.copyWith(contactSelected: null, error: null);

  /// Issues a code for the open contact. The returned link carries the code: open it
  /// and let it go, never keep or log it.
  Future<Uri?> sendContact() => _contactLink((access, id) => _api.sendContactCode(access, id));

  /// Records the notice and returns the link to the number being replaced.
  Future<Uri?> noticeContact() => _contactLink((access, id) => _api.noticeContact(access, id));

  Future<Uri?> _contactLink(Future<Uri> Function(String access, String id) call) async {
    final selected = state.contactSelected;
    if (selected == null || state.busy) return null;
    state = state.copyWith(busy: true, error: null);
    final uri = await _guard((access) => call(access, selected.id), onError: _actionFailed);
    if (uri != null) {
      // Done: the contact leaves this queue.
      state = state.copyWith(
        busy: false,
        contacts: state.contacts?.where((c) => c.id != selected.id).toList(),
      );
    }
    return uri;
  }

  Future<void> selectTab(String status) async {
    if (state.stage != StaffStage.queue || status == state.tab) return;
    state = state.copyWith(tab: status, items: null, listError: null);
    await refresh();
  }

  Future<void> refresh() async {
    final tab = state.tab;
    final items =
        await _guard((access) => _api.enrolments(access, status: tab), onError: (message) {
      if (state.tab == tab) {
        state = state.copyWith(items: state.items ?? const [], listError: message);
      }
    });
    if (items != null && state.stage == StaffStage.queue && state.tab == tab) {
      state = state.copyWith(items: items, listError: null);
    }
  }

  /// Opens the detail screen and loads the fields the list does not carry.
  Future<void> open(EnrolmentItem item) async {
    state = state.copyWith(selected: item, error: null);
    final detail = await _guard((access) => _api.enrolment(access, item.id), onError: (_) {});
    if (detail != null && state.selected?.id == item.id) {
      state = state.copyWith(selected: detail);
    }
  }

  void close() => state = state.copyWith(selected: null, error: null);

  Future<void> approve() => _act((access, id) => _api.approve(access, id));

  Future<void> refuse(String reason) => _act((access, id) => _api.refuse(access, id, reason));

  Future<void> hold(String reason) => _act((access, id) => _api.hold(access, id, reason));

  /// Issues a new confirmation number for the open application. The returned
  /// link carries the number: open it and let it go, never keep or log it.
  Future<Uri?> send() async {
    final selected = state.selected;
    if (selected == null || state.busy) return null;
    state = state.copyWith(busy: true, error: null);
    final uri = await _guard((access) => _api.send(access, selected.id), onError: _actionFailed);
    if (uri != null) _applied(selected.withStatus('code_sent'));
    return uri;
  }

  Future<void> _act(Future<EnrolmentItem> Function(String access, String id) call) async {
    final selected = state.selected;
    if (selected == null || state.busy) return;
    state = state.copyWith(busy: true, error: null);
    final updated = await _guard((access) => call(access, selected.id), onError: _actionFailed);
    if (updated != null) _applied(updated);
  }

  void _actionFailed(String message) => state = state.copyWith(busy: false, error: message);

  /// Shows the changed application and drops it from a list it no longer belongs to.
  void _applied(EnrolmentItem updated) {
    final items = state.items
        ?.map((i) => i.id == updated.id ? updated : i)
        .where((i) => i.status == state.tab)
        .toList();
    state = state.copyWith(
      busy: false,
      items: items,
      selected: state.selected?.id == updated.id ? updated : state.selected,
    );
  }

  /// Runs an authenticated call. An expired access token is renewed once and
  /// the call retried; if the session cannot be renewed the app returns to the
  /// login screen. Any other failure is reported through [onError]. Returns
  /// null on failure.
  Future<T?> _guard<T>(
    Future<T> Function(String access) call, {
    required void Function(String message) onError,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final access = _session.access;
      if (access == null) break;
      try {
        return await call(access);
      } on ApiError catch (e) {
        if (e.status != 401) {
          onError(StaffCopy.actionError(e));
          return null;
        }
      }
      if (attempt > 0) break;
      try {
        if (!await _session.refresh()) break;
      } on ApiError catch (e) {
        onError(StaffCopy.actionError(e));
        return null;
      }
    }
    signOut(message: StaffCopy.sessionExpired);
    return null;
  }
}
