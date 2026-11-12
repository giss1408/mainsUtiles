import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../app/providers.dart';
import '../auth/session.dart';
import 'offer_copy.dart';
import 'offer_models.dart';
import 'offers_api.dart';

const _keep = Object();

class OffersState {
  const OffersState({
    this.offers,
    this.communes = const [],
    this.commune,
    this.page = 0,
    this.hasMore = false,
    this.loading = false,
    this.error,
  });

  /// Null until the first successful load.
  final List<PublicOffer>? offers;
  final List<String> communes;

  /// The commune the list is filtered on; null for all communes.
  final String? commune;

  /// The last page loaded, from 1.
  final int page;
  final bool hasMore;
  final bool loading;

  /// A French message for the current screen.
  final String? error;

  OffersState copyWith({
    Object? offers = _keep,
    List<String>? communes,
    Object? commune = _keep,
    int? page,
    bool? hasMore,
    bool? loading,
    Object? error = _keep,
  }) =>
      OffersState(
        offers: identical(offers, _keep)
            ? this.offers
            : offers as List<PublicOffer>?,
        communes: communes ?? this.communes,
        commune: identical(commune, _keep) ? this.commune : commune as String?,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

/// Loads the published offers, one page at a time, optionally for one commune.
class OffersController extends StateNotifier<OffersState> {
  OffersController({required OffersApi api, required Session session})
      : _api = api,
        _session = session,
        super(const OffersState());

  final OffersApi _api;
  final Session _session;

  /// The first page, for the commune currently chosen.
  Future<void> load() => _fetch(page: 1, commune: state.commune, append: false);

  /// Chooses a commune (null for all) and shows its first page.
  Future<void> setCommune(String? commune) =>
      _fetch(page: 1, commune: commune, append: false);

  /// Adds the next page to the list, if there is one.
  Future<void> loadMore() {
    if (!state.hasMore) return Future.value();
    return _fetch(page: state.page + 1, commune: state.commune, append: true);
  }

  Future<void> _fetch(
      {required int page,
      required String? commune,
      required bool append}) async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await _session.authorized(
        (access) => _api.offers(access, commune: commune, page: page),
      );
      final previous = state.offers ?? const <PublicOffer>[];
      state = state.copyWith(
        offers: append ? [...previous, ...result.offers] : result.offers,
        communes: result.communes,
        commune: commune,
        page: page,
        hasMore: result.hasMore,
        loading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  String _message(ApiError e) {
    if (e.isNetwork) return OfferCopy.offline;
    if (e.status == 401) return OfferCopy.sessionExpired;
    return e.message.isNotEmpty ? e.message : OfferCopy.loadFailed;
  }
}

final offersControllerProvider =
    StateNotifierProvider<OffersController, OffersState>(
  (ref) => OffersController(
    api: ref.watch(offersApiProvider),
    session: ref.watch(sessionProvider),
  ),
);
