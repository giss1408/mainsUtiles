import 'package:dio/dio.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

/// One enrolment application as staff see it.
class EnrolmentItem {
  const EnrolmentItem({
    required this.id,
    required this.phone,
    required this.role,
    required this.kind,
    required this.status,
    required this.flags,
    required this.deviceModel,
    required this.platform,
    required this.integrityVerdict,
    required this.createdAt,
    this.reason,
  });

  factory EnrolmentItem.fromJson(Map<String, dynamic> json) {
    final reason = json['reason'] as String?;
    return EnrolmentItem(
      id: json['id'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String,
      kind: json['kind'] as String,
      status: json['status'] as String,
      flags: ((json['flags'] as List?) ?? const []).map((f) => '$f').toList(),
      deviceModel: (json['device_model'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? '',
      integrityVerdict: (json['integrity_verdict'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      reason: (reason == null || reason.isEmpty) ? null : reason,
    );
  }

  final String id;
  final String phone;
  final String role;
  final String kind;
  final String status;
  final List<String> flags;
  final String deviceModel;
  final String platform;
  final String integrityVerdict;
  final DateTime createdAt;
  final String? reason;

  EnrolmentItem withStatus(String newStatus) => EnrolmentItem(
        id: id,
        phone: phone,
        role: role,
        kind: kind,
        status: newStatus,
        flags: flags,
        deviceModel: deviceModel,
        platform: platform,
        integrityVerdict: integrityVerdict,
        createdAt: createdAt,
        reason: reason,
      );
}

class StaffMe {
  const StaffMe({required this.id, required this.username, required this.permissions});

  factory StaffMe.fromJson(Map<String, dynamic> json) => StaffMe(
        id: json['id'] as String,
        username: json['username'] as String,
        permissions: ((json['permissions'] as List?) ?? const []).map((p) => '$p').toList(),
      );

  final String id;
  final String username;
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);
}

/// The staff endpoints of the API.
class StaffApi {
  StaffApi(this._dio);

  final Dio _dio;

  static const _base = '/api/v1';
  static const _queue = '$_base/staff/enrolments';

  Map<String, dynamic> _json(Response<dynamic> response) =>
      Map<String, dynamic>.from(response.data as Map);

  Options _bearer(String access) => Options(headers: {'Authorization': 'Bearer $access'});

  /// Returns the phone's status: `pending`, `active` or `revoked`.
  Future<String> registerDevice({
    required String username,
    required String password,
    required String deviceId,
    required String deviceModel,
    required String platform,
    required String publicKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/staff/devices',
          data: {
            'username': username,
            'password': password,
            'device_id': deviceId,
            'device_model': deviceModel,
            'platform': platform,
            'public_key': publicKey,
          },
        );
        return _json(response)['status'] as String;
      });

  Future<String> challenge(String deviceId) => guardApi(() async {
        final response =
            await _dio.post<dynamic>('$_base/auth/challenge', data: {'device_id': deviceId});
        return _json(response)['nonce'] as String;
      });

  Future<TokenPair> login({
    required String username,
    required String password,
    required String deviceId,
    required String nonce,
    required String signature,
  }) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_base/staff/auth/login',
          data: {
            'username': username,
            'password': password,
            'device_id': deviceId,
            'nonce': nonce,
            'signature': signature,
          },
        );
        return TokenPair.fromJson(_json(response));
      });

  Future<StaffMe> me(String access) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_base/staff/me', options: _bearer(access));
        return StaffMe.fromJson(_json(response));
      });

  /// The oldest applications in [status] (first page).
  Future<List<EnrolmentItem>> enrolments(String access, {String status = 'pending'}) =>
      guardApi(() async {
        final response = await _dio.get<dynamic>(
          _queue,
          queryParameters: {'status': status},
          options: _bearer(access),
        );
        final results = (_json(response)['results'] as List?) ?? const [];
        return results
            .map((row) => EnrolmentItem.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList();
      });

  Future<EnrolmentItem> enrolment(String access, String id) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_queue/$id', options: _bearer(access));
        return EnrolmentItem.fromJson(_json(response));
      });

  Future<EnrolmentItem> _action(String access, String id, String action, [String? reason]) =>
      guardApi(() async {
        final response = await _dio.post<dynamic>(
          '$_queue/$id/$action',
          data: reason == null ? null : {'reason': reason},
          options: _bearer(access),
        );
        return EnrolmentItem.fromJson(_json(response));
      });

  Future<EnrolmentItem> approve(String access, String id) => _action(access, id, 'approve');

  Future<EnrolmentItem> refuse(String access, String id, String reason) =>
      _action(access, id, 'refuse', reason);

  Future<EnrolmentItem> hold(String access, String id, String reason) =>
      _action(access, id, 'hold', reason);

  /// Issues a new confirmation number and returns the WhatsApp link carrying it.
  Future<Uri> send(String access, String id) => guardApi(() async {
        final response = await _dio.post<dynamic>('$_queue/$id/send', options: _bearer(access));
        return Uri.parse(_json(response)['whatsapp_url'] as String);
      });
}
