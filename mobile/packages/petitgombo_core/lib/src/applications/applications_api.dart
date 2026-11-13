import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../app/providers.dart';
import '../verification/capture.dart';
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

  /// The applicants, and whether payment is available (without it nobody can be accepted).
  Future<(List<ApplicantCard>, bool)> applicants(String access, String offerId) =>
      guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/my-offers/$offerId/applicants',
          options: _bearer(access),
        );
        final available = Map<String, dynamic>.from(response.data as Map)['payment_available'];
        return (_rows(response).map(ApplicantCard.fromJson).toList(), available != false);
      });

  Future<BookingSummary> accept(String access, String offerId, String applicationId) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/my-offers/$offerId/applicants/$applicationId/accept',
          options: _bearer(access),
        );
        return BookingSummary.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  Options _upload(String access) => Options(
        headers: {'Authorization': 'Bearer $access'},
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 1),
      );

  Future<BookingDetail> booking(String access, String offerId) => guardApi(() async {
        final response =
            await _dio.get<dynamic>('$_base/my-offers/$offerId/booking', options: _bearer(access));
        return BookingDetail.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  /// Sends the proof of payment. The screenshot is not kept after it is sent.
  Future<void> submitProof(
    String access,
    String offerId, {
    required int methodId,
    required String reference,
    required CapturedPhoto screenshot,
  }) =>
      guardApi(() async {
        // Built inside the call: a FormData can be sent only once, and a retry needs a new one.
        final form = FormData.fromMap({
          'method_id': methodId,
          'reference': reference,
          'captured_at': screenshot.capturedAt.toUtc().toIso8601String(),
          'screenshot': MultipartFile.fromBytes(
            screenshot.bytes,
            filename: 'proof.jpg',
            contentType: DioMediaType('image', 'jpeg'),
          ),
        });
        await _dio.post<dynamic>(
          '$_base/my-offers/$offerId/booking/payment',
          data: form,
          options: _upload(access),
        );
      });

  Future<Uint8List> bookingPhoto(String access, String offerId) => guardApi(() async {
        final response = await _dio.get<List<int>>(
          '$_base/my-offers/$offerId/booking/photo',
          options: Options(
            headers: {'Authorization': 'Bearer $access'},
            responseType: ResponseType.bytes,
          ),
        );
        return Uint8List.fromList(response.data ?? const []);
      });

  Future<void> cancelBooking(String access, String offerId, String reason) => guardApi(() async {
        await _dio.post<dynamic>(
          '$_base/my-offers/$offerId/booking/cancel',
          data: {'reason': reason},
          options: _bearer(access),
        );
      });

  Future<ReleasedAddress> address(String access, String bookingId) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/my-bookings/$bookingId/address',
          options: _bearer(access),
        );
        return ReleasedAddress.fromJson(Map<String, dynamic>.from(response.data as Map));
      });

  Future<void> cancelJobberBooking(String access, String bookingId, String reason) =>
      guardApi(() async {
        await _dio.post<dynamic>(
          '$_base/my-bookings/$bookingId/cancel',
          data: {'reason': reason},
          options: _bearer(access),
        );
      });
}

final applicationsApiProvider =
    Provider<ApplicationsApi>((ref) => ApplicationsApi(ref.watch(dioProvider)));
