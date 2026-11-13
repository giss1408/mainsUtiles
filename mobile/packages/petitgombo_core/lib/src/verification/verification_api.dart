import 'package:dio/dio.dart';

import '../api/api_client.dart';
import 'capture.dart';
import 'verification_models.dart';

/// The verification endpoints of one role. The householder base is the default.
class VerificationApi {
  VerificationApi(this._dio, {String base = householderBase}) : _base = base;

  static const householderBase = '/api/v1/verification';
  static const jobberBase = '/api/v1/jobber/verification';

  final Dio _dio;
  final String _base;

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

  Future<VerificationChecklist> submitGuarantor(
    String access, {
    required String documentType,
    required CapturedPhoto photo,
    required String guarantorName,
    required String guarantorPhone,
    required String relationship,
  }) =>
      guardApi(() async {
        final form = FormData.fromMap({
          'document_type': documentType,
          'guarantor_name': guarantorName,
          'guarantor_phone': guarantorPhone,
          'relationship': relationship,
          ..._captured(photo),
          'photo': _jpeg(photo, 'photo'),
        });
        return _checklist(
          await _dio.post<dynamic>('$_base/guarantor', data: form, options: _upload(access)),
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

  Map<String, dynamic> _map(Response<dynamic> response) =>
      Map<String, dynamic>.from(response.data as Map);

  Future<({int max, List<TrustedContact> contacts})> contacts(String access) => guardApi(() async {
        final data = _map(await _dio.get<dynamic>('$_base/contacts', options: _bearer(access)));
        return (
          max: (data['max'] as num?)?.toInt() ?? 2,
          contacts: ((data['contacts'] as List?) ?? const [])
              .map((c) => TrustedContact.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList(),
        );
      });

  Future<TrustedContact> addContact(
    String access, {
    required String name,
    required String phone,
    required String relationship,
  }) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/contacts',
          data: {'name': name, 'phone': phone, 'relationship': relationship},
          options: _bearer(access),
        );
        return TrustedContact.fromJson(_map(response));
      });

  Future<TrustedContact> replaceContact(
    String access,
    String id, {
    required String name,
    required String phone,
    required String relationship,
  }) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/contacts/$id/replace',
          data: {'name': name, 'phone': phone, 'relationship': relationship},
          options: _bearer(access),
        );
        return TrustedContact.fromJson(_map(response));
      });

  Future<TrustedContact> requestContactCode(String access, String id) => guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/contacts/$id/code',
          options: _bearer(access),
        );
        return TrustedContact.fromJson(_map(response));
      });

  Future<TrustedContact> confirmContact(String access, String id, String code) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/contacts/$id/confirm',
          data: {'code': code},
          options: _bearer(access),
        );
        return TrustedContact.fromJson(_map(response));
      });

  Future<({BriefingStep progress, List<BriefingCard> cards})> briefing(String access) =>
      guardApi(() async {
        final data = _map(await _dio.get<dynamic>('$_base/briefing', options: _bearer(access)));
        return (
          progress: BriefingStep.fromJson(Map<String, dynamic>.from(data['progress'] as Map)),
          cards: ((data['cards'] as List?) ?? const [])
              .map((c) => BriefingCard.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList(),
        );
      });

  Future<BriefingAnswer> answerCard(String access, String cardId, int choice) => guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/briefing/$cardId/answer',
          data: {'choice': choice},
          options: _bearer(access),
        );
        return BriefingAnswer.fromJson(_map(response));
      });

  CapturedPhoto _withPosition(CapturedPhoto photo, (double, double)? position) =>
      CapturedPhoto(bytes: photo.bytes, capturedAt: photo.capturedAt, position: position);
}
