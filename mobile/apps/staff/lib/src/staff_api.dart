import 'dart:typed_data';

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

/// One trusted contact waiting for staff. The number is never part of it: it only
/// travels inside the WhatsApp link the server returns on send.
class ContactItem {
  const ContactItem({
    required this.id,
    required this.relationship,
    required this.action,
    required this.createdAt,
    this.name,
    this.jobberName,
  });

  factory ContactItem.fromJson(Map<String, dynamic> json) => ContactItem(
        id: json['id'] as String,
        relationship: json['relationship'] as String,
        action: json['action'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        name: json['name'] as String?,
        jobberName: json['jobber_name'] as String?,
      );

  final String id;
  final String relationship;

  /// `send` (a code to send) or `notice` (an old contact to warn).
  final String action;
  final DateTime createdAt;

  /// Only known once the detail is open.
  final String? name;
  final String? jobberName;
}

/// A payment waiting for staff. The list carries no reference; the detail does.
class PaymentItem {
  const PaymentItem({
    required this.id,
    required this.categoryName,
    required this.startsAt,
    required this.amountXof,
    required this.methodLabel,
    required this.submittedAt,
    required this.late,
    required this.action,
    this.feeXof,
    this.reference,
    this.methodNumber,
    this.seenBefore,
  });

  factory PaymentItem.fromJson(Map<String, dynamic> json) => PaymentItem(
        id: json['id'] as String,
        categoryName: (json['category_name'] as String?) ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        amountXof: (json['amount_xof'] as num).toInt(),
        methodLabel: (json['method_label'] as String?) ?? '',
        submittedAt: DateTime.parse(json['submitted_at'] as String).toLocal(),
        late: json['late'] == true,
        action: (json['action'] as String?) ?? 'check',
        feeXof: (json['fee_xof'] as num?)?.toInt(),
        reference: json['reference'] as String?,
        methodNumber: json['method_number'] as String?,
        seenBefore: json['seen_before'] as bool?,
      );

  final String id;
  final String categoryName;
  final DateTime startsAt;
  final int amountXof;
  final String methodLabel;
  final DateTime submittedAt;
  final bool late;

  /// `check` (a proof to verify) or `refund` (money to send back).
  final String action;

  /// Only on the detail.
  final int? feeXof;
  final String? reference;
  final String? methodNumber;
  final bool? seenBefore;
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

  /// Exchanges the refresh token for a new pair. Each refresh token works once.
  Future<TokenPair> refresh(String refreshToken) => guardApi(() async {
        final response =
            await _dio.post<dynamic>('$_base/auth/refresh', data: {'refresh': refreshToken});
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

  static const _contacts = '$_base/staff/contacts';

  /// The oldest contacts in [file] (`send` or `notice`), first page. No names, no numbers.
  Future<List<ContactItem>> contacts(String access, {String file = 'send'}) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          _contacts,
          queryParameters: {'file': file},
          options: _bearer(access),
        );
        final results = (_json(response)['results'] as List?) ?? const [];
        return results
            .map((row) => ContactItem.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList();
      });

  /// The contact's name and the jobber's name. Opening it is audited by the server.
  Future<ContactItem> contact(String access, String id) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_contacts/$id', options: _bearer(access));
        return ContactItem.fromJson(_json(response));
      });

  /// Issues a code and returns the WhatsApp link carrying it.
  Future<Uri> sendContactCode(String access, String id) => guardApi(() async {
        final response = await _dio.post<dynamic>('$_contacts/$id/send', options: _bearer(access));
        return Uri.parse(_json(response)['whatsapp_url'] as String);
      });

  /// Records the notice and returns the WhatsApp link to the number being replaced.
  Future<Uri> noticeContact(String access, String id) => guardApi(() async {
        final response =
            await _dio.post<dynamic>('$_contacts/$id/notice', options: _bearer(access));
        return Uri.parse(_json(response)['whatsapp_url'] as String);
      });

  static const _payments = '$_base/staff/payments';

  /// The oldest payments in [file] (`check` or `refund`), first page. No reference, no name.
  Future<List<PaymentItem>> payments(String access, {String file = 'check'}) => guardApi(() async {
        final response = await _dio.get<dynamic>(
          _payments,
          queryParameters: {'file': file},
          options: _bearer(access),
        );
        final results = (_json(response)['results'] as List?) ?? const [];
        return results
            .map((row) => PaymentItem.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList();
      });

  /// The reference and the method's number. Opening it is audited by the server.
  Future<PaymentItem> payment(String access, String id) => guardApi(() async {
        final response = await _dio.get<dynamic>('$_payments/$id', options: _bearer(access));
        return PaymentItem.fromJson(_json(response));
      });

  Future<Uint8List> paymentProof(String access, String id) => guardApi(() async {
        final response = await _dio.get<List<int>>(
          '$_payments/$id/proof',
          options: Options(
            headers: {'Authorization': 'Bearer $access'},
            responseType: ResponseType.bytes,
          ),
        );
        return Uint8List.fromList(response.data ?? const []);
      });

  Future<void> confirmPayment(
    String access,
    String id, {
    required bool amountMatches,
    required bool referenceMatches,
  }) =>
      guardApi(() async {
        await _dio.post<dynamic>(
          '$_payments/$id/confirm',
          data: {'amount_matches': amountMatches, 'reference_matches': referenceMatches},
          options: _bearer(access),
        );
      });

  Future<void> refusePayment(String access, String id, String reason) => guardApi(() async {
        await _dio.post<dynamic>(
          '$_payments/$id/refuse',
          data: {'reason': reason},
          options: _bearer(access),
        );
      });

  Future<void> refundPayment(String access, String id, String reference) => guardApi(() async {
        await _dio.post<dynamic>(
          '$_payments/$id/refund',
          data: {'reference': reference},
          options: _bearer(access),
        );
      });
}
