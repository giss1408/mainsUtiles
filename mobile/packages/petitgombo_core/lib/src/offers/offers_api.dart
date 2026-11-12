import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../app/providers.dart';
import 'offer_models.dart';

/// The job-offer endpoints, for the householder and the jobber.
class OffersApi {
  OffersApi(this._dio);

  final Dio _dio;

  static const _base = '/api/v1';

  Options _bearer(String access) => Options(headers: {'Authorization': 'Bearer $access'});

  String _mine(String id) => '$_base/my-offers/$id';

  Future<(List<OfferCategory>, OfferLimits)> categories(String access) => guardApi(() async {
        final response =
            await _dio.get<dynamic>('$_base/offer-categories', options: _bearer(access));
        final data = Map<String, dynamic>.from(response.data as Map);
        final categories = (data['categories'] as List)
            .map((c) => OfferCategory.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
        final limits = OfferLimits.fromJson(Map<String, dynamic>.from(data['limits'] as Map));
        return (categories, limits);
      });

  Future<MyOffers> myOffers(String access) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_base/my-offers', options: _bearer(access));
        final data = Map<String, dynamic>.from(response.data as Map);
        return MyOffers(
          canPublish: data['can_publish'] as bool,
          reviewHours: (data['review_hours'] as num).toInt(),
          offers: (data['offers'] as List)
              .map((o) => MyOffer.fromJson(Map<String, dynamic>.from(o as Map)))
              .toList(),
        );
      });

  Future<MyOffer> createDraft(String access, OfferDraft draft) => guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/my-offers',
          data: draft.toJson(),
          options: _bearer(access),
        );
        return _offer(response.data);
      });

  Future<MyOffer> updateDraft(String access, String id, OfferDraft draft) => guardApi(() async {
        final response = await _dio.patch<dynamic>(
          _mine(id),
          data: draft.toJson(),
          options: _bearer(access),
        );
        return _offer(response.data);
      });

  Future<void> deleteDraft(String access, String id) => guardApi(() async {
        await _dio.delete<dynamic>(_mine(id), options: _bearer(access));
      });

  Future<MyOffer> send(String access, String id) => _action(access, '${_mine(id)}/send');

  Future<MyOffer> withdraw(String access, String id) => _action(access, '${_mine(id)}/withdraw');

  Future<MyOffer> copy(String access, String id) => _action(access, '${_mine(id)}/copy');

  Future<OfferPage> offers(String access, {String? commune, int page = 1}) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/offers',
          queryParameters: {'page': page, if (commune != null) 'commune': commune},
          options: _bearer(access),
        );
        final data = Map<String, dynamic>.from(response.data as Map);
        return OfferPage(
          offers: (data['results'] as List)
              .map((o) => PublicOffer.fromJson(Map<String, dynamic>.from(o as Map)))
              .toList(),
          communes: ((data['communes'] as List?) ?? const []).map((c) => '$c').toList(),
          hasMore: data['next'] != null,
        );
      });

  Future<PublicOffer> offer(String access, String id) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_base/offers/$id', options: _bearer(access));
        return PublicOffer.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  Future<MyOffer> _action(String access, String path) => guardApi(() async {
        final response = await _dio.post<dynamic>(path, options: _bearer(access));
        return _offer(response.data);
      });

  MyOffer _offer(Object? data) => MyOffer.fromJson(Map<String, dynamic>.from(data as Map));
}

final offersApiProvider = Provider<OffersApi>((ref) => OffersApi(ref.watch(dioProvider)));
