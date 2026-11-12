class EnrolmentStatus {
  const EnrolmentStatus({
    required this.id,
    required this.status,
    required this.reason,
    required this.responseHours,
  });

  factory EnrolmentStatus.fromJson(Map<String, dynamic> json) {
    final reason = json['reason'] as String?;
    return EnrolmentStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      reason: (reason == null || reason.isEmpty) ? null : reason,
      responseHours: (json['response_hours'] as num?)?.toInt() ?? 24,
    );
  }

  final String id;
  final String status;
  final String? reason;
  final int responseHours;
}

class TokenPair {
  const TokenPair({required this.access, required this.refresh});

  factory TokenPair.fromJson(Map<String, dynamic> json) =>
      TokenPair(access: json['access'] as String, refresh: json['refresh'] as String);

  final String access;
  final String refresh;
}

class Me {
  const Me({required this.id, required this.phone, required this.role});

  factory Me.fromJson(Map<String, dynamic> json) =>
      Me(id: json['id'] as String, phone: json['phone'] as String, role: json['role'] as String);

  final String id;
  final String phone;
  final String role;
}
