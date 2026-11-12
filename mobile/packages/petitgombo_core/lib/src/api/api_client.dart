import 'package:dio/dio.dart';

import '../app/app_role.dart';
import 'api_error.dart';
import 'models.dart';

/// Turns a Dio failure into an [ApiError].
ApiError apiErrorFrom(DioException e) {
  final response = e.response;
  if (response == null) {
    return const ApiError(code: 'network', message: '');
  }
  final data = response.data;
  if (data is Map && data['error'] is String) {
    return ApiError(
      code: data['error'] as String,
      message: (data['message'] as String?) ?? '',
      status: response.statusCode,
    );
  }
  return ApiError(code: 'http_${response.statusCode}', message: '', status: response.statusCode);
}

/// Runs [call] and converts failures to [ApiError].
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw apiErrorFrom(e);
  }
}

/// The user-facing API: enrolment and sign-in.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  static const _base = '/api/v1';

  Map<String, dynamic> _json(Response<dynamic> response) =>
      Map<String, dynamic>.from(response.data as Map);

  Options _enrolmentToken(String clientToken) =>
      Options(headers: {'X-Enrolment-Token': clientToken});

  Future<EnrolmentStatus> apply({
    required String phone,
    required AppRole role,
    required String deviceId,
    required String deviceModel,
    required String platform,
    required String publicKey,
    required String clientToken,
  }) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/enrolment/applications',
          data: {
            'phone': phone,
            'role': role.name,
            'device_id': deviceId,
            'device_model': deviceModel,
            'platform': platform,
            'public_key': publicKey,
            'client_token': clientToken,
          },
        );
        return EnrolmentStatus.fromJson(_json(response));
      });

  Future<EnrolmentStatus> status(String id, String clientToken) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/enrolment/applications/$id',
          options: _enrolmentToken(clientToken),
        );
        return EnrolmentStatus.fromJson(_json(response));
      });

  Future<void> confirm(String id, String clientToken, String code) => guardApi(() async {
        await _dio.post<dynamic>(
          '$_base/enrolment/applications/$id/confirm',
          data: {'code': code},
          options: _enrolmentToken(clientToken),
        );
      });

  Future<String> challenge(String deviceId) => guardApi(() async {
        final response =
            await _dio.post<dynamic>('$_base/auth/challenge', data: {'device_id': deviceId});
        return _json(response)['nonce'] as String;
      });

  Future<TokenPair> token(String deviceId, String nonce, String signature) => guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/auth/token',
          data: {'device_id': deviceId, 'nonce': nonce, 'signature': signature},
        );
        return TokenPair.fromJson(_json(response));
      });

  Future<TokenPair> refresh(String refreshToken) => guardApi(() async {
        final response =
            await _dio.post<dynamic>('$_base/auth/refresh', data: {'refresh': refreshToken});
        return TokenPair.fromJson(_json(response));
      });

  Future<Me> me(String accessToken) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          '$_base/me',
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        );
        return Me.fromJson(_json(response));
      });
}
