import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import 'verification_api.dart';
import 'verification_controller.dart';
import 'verification_copy.dart';
import 'verification_models.dart';

const _keep = Object();

class BriefingState {
  const BriefingState({
    this.cards,
    this.progress,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<BriefingCard>? cards;
  final BriefingStep? progress;
  final bool loading;
  final bool sending;
  final String? error;

  BriefingState copyWith({
    List<BriefingCard>? cards,
    BriefingStep? progress,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      BriefingState(
        cards: cards ?? this.cards,
        progress: progress ?? this.progress,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// The safety briefing: cards read one at a time, each answered with a choice.
class BriefingController extends StateNotifier<BriefingState> {
  BriefingController({
    required VerificationApi api,
    required Session session,
    required Future<void> Function() refreshChecklist,
  })  : _api = api,
        _session = session,
        _refreshChecklist = refreshChecklist,
        super(const BriefingState());

  final VerificationApi _api;
  final Session _session;
  final Future<void> Function() _refreshChecklist;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final data = await _session.authorized(_api.briefing);
      state = state.copyWith(cards: data.cards, progress: data.progress, loading: false);
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  void clearError() => state = state.copyWith(error: null);

  /// Null when the answer could not be checked; the screen shows [BriefingState.error].
  Future<BriefingAnswer?> answer(String cardId, int choice) async {
    if (state.sending) return null;
    state = state.copyWith(sending: true, error: null);
    try {
      final answer = await _session.authorized((access) => _api.answerCard(access, cardId, choice));
      final cards = state.cards;
      final marked = answer.correct && cards != null
          ? [for (final card in cards) card.id == cardId ? card.markAnswered() : card]
          : null;
      state = state.copyWith(
        sending: false,
        cards: marked,
        progress: marked == null ? null : _progressAfter(marked, answer.complete),
      );
      if (answer.complete) await _refreshChecklist();
      return answer;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: _message(e));
      return null;
    }
  }

  /// The counts the screen shows, kept in step with the cards just answered.
  BriefingStep? _progressAfter(List<BriefingCard> cards, bool complete) {
    final progress = state.progress;
    if (progress == null) return null;
    final answered = cards.where((card) => card.answered).length;
    final status = complete || progress.status == StepStatus.confirmed
        ? StepStatus.confirmed
        : answered > 0
            ? StepStatus.inProgress
            : progress.status;
    return BriefingStep(
      status: status,
      answered: answered,
      total: progress.total,
      newCards: progress.total - answered,
    );
  }

  String _message(ApiError e) {
    if (e.isNetwork) return VerificationCopy.offline;
    if (e.status == 401) return VerificationCopy.sessionExpired;
    return e.message.isNotEmpty ? e.message : VerificationCopy.genericError;
  }
}

final briefingControllerProvider = StateNotifierProvider<BriefingController, BriefingState>(
  (ref) => BriefingController(
    api: ref.watch(verificationApiProvider),
    session: ref.watch(sessionProvider),
    refreshChecklist: () => ref.read(verificationControllerProvider.notifier).load(),
  ),
);
