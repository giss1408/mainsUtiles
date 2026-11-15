import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'staff_api.dart';
import 'staff_controller.dart';

const _keep = Object();

class OpsState {
  const OpsState({
    this.busy = false,
    this.error,
    this.listError,
    this.messages,
    this.messageSelected,
    this.jobsTab = 'payouts',
    this.payouts,
    this.payoutSelected,
    this.disputes,
    this.disputeSelected,
    this.alerts,
  });

  /// An action is in progress.
  final bool busy;

  /// A message for the open detail.
  final String? error;
  final String? listError;

  /// The messages to send; null while it loads. Items carry no text.
  final List<MessageItem>? messages;

  /// The message open in the detail screen, with its text. Cleared on close.
  final MessageItem? messageSelected;

  /// `payouts` or `disputes`.
  final String jobsTab;
  final List<PayoutItem>? payouts;

  /// The payout open in the detail screen, with the jobber's phone. Cleared on close.
  final PayoutItem? payoutSelected;
  final List<DisputeItem>? disputes;

  /// The dispute open in the detail screen, with its text. Cleared on close.
  final DisputeItem? disputeSelected;

  /// Counts for the section badges; null until loaded.
  final StaffAlerts? alerts;

  /// A detail screen is open.
  bool get hasDetail =>
      messageSelected != null || payoutSelected != null || disputeSelected != null;

  OpsState copyWith({
    bool? busy,
    Object? error = _keep,
    Object? listError = _keep,
    Object? messages = _keep,
    Object? messageSelected = _keep,
    String? jobsTab,
    Object? payouts = _keep,
    Object? payoutSelected = _keep,
    Object? disputes = _keep,
    Object? disputeSelected = _keep,
    Object? alerts = _keep,
  }) =>
      OpsState(
        busy: busy ?? this.busy,
        error: identical(error, _keep) ? this.error : error as String?,
        listError: identical(listError, _keep) ? this.listError : listError as String?,
        messages: identical(messages, _keep) ? this.messages : messages as List<MessageItem>?,
        messageSelected: identical(messageSelected, _keep)
            ? this.messageSelected
            : messageSelected as MessageItem?,
        jobsTab: jobsTab ?? this.jobsTab,
        payouts: identical(payouts, _keep) ? this.payouts : payouts as List<PayoutItem>?,
        payoutSelected:
            identical(payoutSelected, _keep) ? this.payoutSelected : payoutSelected as PayoutItem?,
        disputes: identical(disputes, _keep) ? this.disputes : disputes as List<DisputeItem>?,
        disputeSelected: identical(disputeSelected, _keep)
            ? this.disputeSelected
            : disputeSelected as DisputeItem?,
        alerts: identical(alerts, _keep) ? this.alerts : alerts as StaffAlerts?,
      );
}

/// The day-to-day operations of the staff app: messages to send on WhatsApp, payouts, disputes
/// and the counts of what waits. Sign-in and the session stay with the [StaffController].
class OpsController extends StateNotifier<OpsState> {
  OpsController({required StaffApi api, required StaffController staff, OpsState? initial})
      : _api = api,
        _staff = staff,
        super(initial ?? const OpsState());

  final StaffApi _api;
  final StaffController _staff;

  /// Everything is dropped at sign-out.
  void reset() => state = const OpsState();

  /// Called when the agent enters a section: loads its queue and the counts.
  Future<void> enter(StaffSection section) async {
    state = state.copyWith(error: null, listError: null);
    if (section == StaffSection.messages) {
      state = state.copyWith(messages: null);
      await refreshMessages();
    } else if (section == StaffSection.jobs) {
      final me = _staff.state.me;
      if (me != null && !me.can('make_payout')) state = state.copyWith(jobsTab: 'disputes');
      await _refreshJobs();
    }
    await refreshAlerts();
  }

  Future<void> refreshAlerts() async {
    final alerts = await _staff.guard(_api.alerts, onError: (_) {});
    if (alerts != null && mounted) state = state.copyWith(alerts: alerts);
  }

  // ---- Messages ----

  Future<void> refreshMessages() async {
    final rows = await _staff.guard(_api.messages, onError: (message) {
      state = state.copyWith(messages: state.messages ?? const <MessageItem>[], listError: message);
    });
    if (rows != null) state = state.copyWith(messages: rows, listError: null);
  }

  /// Opens a message and loads the text the list does not carry (the server audits it).
  Future<void> openMessage(MessageItem item) async {
    state = state.copyWith(messageSelected: item, error: null);
    final detail = await _staff.guard((access) => _api.message(access, item.id), onError: (_) {});
    if (detail != null && state.messageSelected?.id == item.id) {
      state = state.copyWith(messageSelected: detail);
    }
  }

  void closeMessage() => state = state.copyWith(messageSelected: null, error: null);

  /// Marks the open message sent and returns the WhatsApp link: open it and let it go, never keep
  /// or log it. Null when the server refused. The message leaves the queue once it is sent, or
  /// when the server says it is gone (no longer true, or sent by someone else); after any other
  /// failure it is still to send, so it stays.
  Future<Uri?> sendMessage() async {
    final selected = state.messageSelected;
    if (selected == null || state.busy) return null;
    state = state.copyWith(busy: true, error: null);
    String? failure;
    var gone = false;
    final uri = await _staff.guard(
      (access) async {
        try {
          return await _api.sendMessage(access, selected.id);
        } on ApiError catch (e) {
          gone = e.code == 'message_stale' || e.code == 'invalid_state' || e.status == 404;
          rethrow;
        }
      },
      onError: (message) => failure = message,
    );
    if (!mounted) return uri;
    state = state.copyWith(
      busy: false,
      error: failure,
      messages: uri != null || gone
          ? state.messages?.where((m) => m.id != selected.id).toList()
          : state.messages,
    );
    await refreshAlerts();
    return uri;
  }

  // ---- Payouts and disputes ----

  Future<void> selectJobsTab(String tab) async {
    if (tab == state.jobsTab) return;
    state = state.copyWith(jobsTab: tab, listError: null);
    await _refreshJobs();
  }

  Future<void> _refreshJobs() => state.jobsTab == 'disputes' ? refreshDisputes() : refreshPayouts();

  Future<void> refreshJobs() async {
    await _refreshJobs();
    await refreshAlerts();
  }

  Future<void> refreshPayouts() async {
    final rows = await _staff.guard(_api.payouts, onError: (message) {
      state = state.copyWith(payouts: state.payouts ?? const <PayoutItem>[], listError: message);
    });
    if (rows != null) state = state.copyWith(payouts: rows, listError: null);
  }

  /// Opens a payout and loads the jobber's phone (the server audits it). Dropped by [closePayout].
  Future<void> openPayout(PayoutItem item) async {
    state = state.copyWith(payoutSelected: item, error: null);
    final detail = await _staff.guard((access) => _api.payout(access, item.id), onError: (_) {});
    if (detail != null && state.payoutSelected?.id == item.id) {
      state = state.copyWith(payoutSelected: detail);
    }
  }

  void closePayout() => state = state.copyWith(payoutSelected: null, error: null);

  Future<bool> payPayout(String reference) async {
    final selected = state.payoutSelected;
    if (selected == null || state.busy) return false;
    final done = await _decide((access) => _api.payPayout(access, selected.id, reference));
    if (done) {
      state = state.copyWith(
        payouts: state.payouts?.where((p) => p.id != selected.id).toList(),
        payoutSelected: null,
      );
      await refreshAlerts();
    }
    return done;
  }

  Future<void> refreshDisputes() async {
    final rows = await _staff.guard(_api.disputes, onError: (message) {
      state = state.copyWith(disputes: state.disputes ?? const <DisputeItem>[], listError: message);
    });
    if (rows != null) state = state.copyWith(disputes: rows, listError: null);
  }

  /// Opens a dispute and loads what was written (the server audits it). Dropped by [closeDispute].
  Future<void> openDispute(DisputeItem item) async {
    state = state.copyWith(disputeSelected: item, error: null);
    final detail = await _staff.guard((access) => _api.dispute(access, item.id), onError: (_) {});
    if (detail != null && state.disputeSelected?.id == item.id) {
      state = state.copyWith(disputeSelected: detail);
    }
  }

  void closeDispute() => state = state.copyWith(disputeSelected: null, error: null);

  Future<bool> resolveDispute(String outcome, String note, {int? jobberXof}) async {
    final selected = state.disputeSelected;
    if (selected == null || state.busy) return false;
    final done = await _decide(
      (access) => _api.resolveDispute(access, selected.id,
          outcome: outcome, note: note, jobberXof: jobberXof),
    );
    if (done) {
      state = state.copyWith(
        disputes: state.disputes?.where((d) => d.id != selected.id).toList(),
        disputeSelected: null,
      );
      await refreshAlerts();
    }
    return done;
  }

  /// Runs a decision on the open item. On a refusal the detail stays open with the server's words.
  Future<bool> _decide(Future<void> Function(String access) call) async {
    state = state.copyWith(busy: true, error: null);
    String? failure;
    final done = await _staff.guard<bool>((access) async {
      await call(access);
      return true;
    }, onError: (message) => failure = message);
    state = state.copyWith(busy: false, error: failure);
    return done == true;
  }
}
