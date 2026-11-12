import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import 'offer_copy.dart';
import 'offer_models.dart';
import 'offers_api.dart';

const _keep = Object();

class MyOffersState {
  const MyOffersState({
    this.data,
    this.categories = const [],
    this.limits,
    this.loading = false,
    this.sending = false,
    this.error,
  });

  /// Null until the first successful load.
  final MyOffers? data;
  final List<OfferCategory> categories;
  final OfferLimits? limits;
  final bool loading;

  /// True while one change (save, send, withdraw, delete, copy) is in progress.
  final bool sending;

  /// A French message for the current screen.
  final String? error;

  MyOffersState copyWith({
    MyOffers? data,
    List<OfferCategory>? categories,
    OfferLimits? limits,
    bool? loading,
    bool? sending,
    Object? error = _keep,
  }) =>
      MyOffersState(
        data: data ?? this.data,
        categories: categories ?? this.categories,
        limits: limits ?? this.limits,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// Loads the householder's offers and the catalogue, and applies each change.
class MyOffersController extends StateNotifier<MyOffersState> {
  MyOffersController({required OffersApi api, required Session session})
      : _api = api,
        _session = session,
        super(const MyOffersState());

  final OffersApi _api;
  final Session _session;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final mine = await _session.authorized(_api.myOffers);
      final (categories, limits) = await _session.authorized(_api.categories);
      state = state.copyWith(
        data: mine,
        categories: categories,
        limits: limits,
        loading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  /// Creates the draft when [id] is null, otherwise updates it. Null on failure.
  Future<MyOffer?> saveDraft(OfferDraft draft, {String? id}) => _change(
        id ?? '',
        (access) =>
            id == null ? _api.createDraft(access, draft) : _api.updateDraft(access, id, draft),
      );

  Future<MyOffer?> publish(String id) => _change(id, (access) => _api.send(access, id));

  Future<MyOffer?> withdraw(String id) => _change(id, (access) => _api.withdraw(access, id));

  Future<MyOffer?> copy(String id) => _change(
        id,
        (access) => _api.copy(access, id),
      );

  /// True when the draft is gone.
  Future<bool> delete(String id) async {
    if (state.sending) return false;
    state = state.copyWith(sending: true, error: null);
    try {
      await _session.authorized((access) => _api.deleteDraft(access, id));
      final data = state.data;
      if (data != null) {
        state = state.copyWith(
          data: _withOffers(data, data.offers.where((o) => o.id != id).toList()),
        );
      }
      state = state.copyWith(sending: false);
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(sending: false, error: _message(e));
      return false;
    }
  }

  /// Runs one change and puts the answer into the list. When the server says the
  /// offer is no longer in a state to change, an earlier attempt probably arrived
  /// and its answer was lost: the list is reloaded and the offer as it now stands
  /// is returned.
  Future<MyOffer?> _change(String id, Future<MyOffer> Function(String access) call) async {
    if (state.sending) return null;
    state = state.copyWith(sending: true, error: null);
    try {
      final offer = await _session.authorized(call);
      _put(offer);
      state = state.copyWith(sending: false);
      return offer;
    } on ApiError catch (e) {
      if (e.code == 'invalid_state' && id.isNotEmpty && await _reloadOffers()) {
        final found = _find(id);
        if (found != null) {
          state = state.copyWith(sending: false, error: null);
          return found;
        }
      }
      state = state.copyWith(sending: false, error: _message(e));
      return null;
    }
  }

  /// Reloads only the list of offers. False when that fails.
  Future<bool> _reloadOffers() async {
    try {
      final mine = await _session.authorized(_api.myOffers);
      state = state.copyWith(data: mine);
      return true;
    } on ApiError {
      return false;
    }
  }

  MyOffer? _find(String id) {
    for (final offer in state.data?.offers ?? const <MyOffer>[]) {
      if (offer.id == id) return offer;
    }
    return null;
  }

  /// Replaces the offer with the same id, or puts a new one at the top.
  void _put(MyOffer offer) {
    final data = state.data;
    if (data == null) return;
    final rest = data.offers.where((o) => o.id != offer.id).toList();
    state = state.copyWith(data: _withOffers(data, [offer, ...rest]));
  }

  MyOffers _withOffers(MyOffers data, List<MyOffer> offers) =>
      MyOffers(canPublish: data.canPublish, reviewHours: data.reviewHours, offers: offers);

  String _message(ApiError e) {
    if (e.isNetwork) return OfferCopy.offline;
    if (e.status == 401) return OfferCopy.sessionExpired;
    return e.message.isNotEmpty ? e.message : OfferCopy.genericError;
  }
}

final myOffersControllerProvider = StateNotifierProvider<MyOffersController, MyOffersState>(
  (ref) => MyOffersController(
    api: ref.watch(offersApiProvider),
    session: ref.watch(sessionProvider),
  ),
);
