import 'package:dio/dio.dart';

import '../api/api_client.dart';
import 'capture.dart';
import 'verification_models.dart';

/// The householder verification endpoints.
class VerificationApi {
  VerificationApi(this._dio);

  final Dio _dio;

  static const _base = '/api/v1/verification';

  Options _bearer(String access) => Options(headers: {'Authorization': 'Bearer $access'});

  /// Photos on a slow mobile connection need far longer than an ordinary call:
  /// the default send limit covers the whole upload.
  Options _upload(String access) => Options(
        headers: {'Authorization': 'Bearer $access'},
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 1),
      );

  VerificationChecklist _checklist(Response<dynamic> response) =>
      VerificationChecklist.fromJson(Map<String, dynamic>.from(response.data as Map));

  MultipartFile _jpeg(CapturedPhoto photo, String name) => MultipartFile.fromBytes(
        photo.bytes,
        filename: '$name.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      );

  Map<String, dynamic> _captured(CapturedPhoto photo) => {
        'captured_at': photo.capturedAt.toUtc().toIso8601String(),
        if (photo.position != null) 'lat': '${photo.position!.$1}',
        if (photo.position != null) 'lng': '${photo.position!.$2}',
      };

  Future<VerificationChecklist> checklist(String access) => guardApi(
        () async => _checklist(await _dio.get<dynamic>(_base, options: _bearer(access))),
      );

  Future<VerificationChecklist> submitIdentity(
    String access, {
    required String documentType,
    required CapturedPhoto front,
    required CapturedPhoto back,
    required CapturedPhoto selfie,
  }) =>
      guardApi(() async {
        // Built inside the call: a FormData can be sent only once, and a retry needs a new one.
        final form = FormData.fromMap({
          'document_type': documentType,
          ..._captured(selfie.position == null ? _withPosition(selfie, front.position) : selfie),
          'front': _jpeg(front, 'front'),
          'back': _jpeg(back, 'back'),
          'selfie': _jpeg(selfie, 'selfie'),
        });
        return _checklist(
          await _dio.post<dynamic>('$_base/identity', data: form, options: _upload(access)),
        );
      });

  Future<VerificationChecklist> submitAddress(
    String access, {
    required String documentType,
    required CapturedPhoto photo,
    required String commune,
    required String quartier,
  }) =>
      guardApi(() async {
        final form = FormData.fromMap({
          'document_type': documentType,
          'commune': commune,
          'quartier': quartier,
          ..._captured(photo),
          'photo': _jpeg(photo, 'photo'),
        });
        return _checklist(
          await _dio.post<dynamic>('$_base/address', data: form, options: _upload(access)),
        );
      });

  Future<VerificationChecklist> recordHomeLocation(String access, DevicePosition position) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/home-location',
          data: {
            'lat': position.lat,
            'lng': position.lng,
            'accuracy_m': position.accuracyM,
            'mock_location': position.mocked,
            'captured_at': position.capturedAt.toUtc().toIso8601String(),
          },
          options: _bearer(access),
        );
        return _checklist(response);
      });

  CapturedPhoto _withPosition(CapturedPhoto photo, (double, double)? position) =>
      CapturedPhoto(bytes: photo.bytes, capturedAt: photo.capturedAt, position: position);
}
