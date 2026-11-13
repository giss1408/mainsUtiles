import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../app/providers.dart';
import 'application_models.dart';

/// The application endpoints, for the jobber and the householder.
class ApplicationsApi {
  ApplicationsApi(this._dio);

  final Dio _dio;

  static const _base = '/api/v1';

  Options _bearer(String access) => Options(headers: {'Authorization': 'Bearer $access'});

  List<Map<String, dynamic>> _rows(Response<dynamic> response) =>
      ((Map<String, dynamic>.from(response.data as Map)['results'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  Future<ApplicationReceipt> apply(String access, String offerId, String message) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/offers/$offerId/apply',
          data: {'message': message},
          options: _bearer(access),
        );
        return ApplicationReceipt.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  Future<List<JobberApplication>> mine(String access) => guardApi(() async {
        final response =
            await _dio.get<dynamic>('$_base/my-applications', options: _bearer(access));
        return _rows(response).map(JobberApplication.fromJson).toList();
      });

  Future<ApplicationReceipt> withdraw(String access, String id) => guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/my-applications/$id/withdraw',
          options: _bearer(access),
        );
        return ApplicationReceipt.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  Future<List<JobberBooking>> myBookings(String access) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_base/my-bookings', options: _bearer(access));
        return _rows(response).map(JobberBooking.fromJson).toList();
      });

  Future<List<ApplicantCard>> applicants(String access, String offerId) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/my-offers/$offerId/applicants',
          options: _bearer(access),
        );
        return _rows(response).map(ApplicantCard.fromJson).toList();
      });

  Future<BookingSummary> accept(String access, String offerId, String applicationId) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/my-offers/$offerId/applicants/$applicationId/accept',
          options: _bearer(access),
        );
        return BookingSummary.fromJson(Map<String, dynamic>.from(response.data as Map));
      });
}

final applicationsApiProvider =
    Provider<ApplicationsApi>((ref) => ApplicationsApi(ref.watch(dioProvider)));
