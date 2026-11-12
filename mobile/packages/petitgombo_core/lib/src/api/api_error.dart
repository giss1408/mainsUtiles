/// A failed API call. [code] is the server's `error` value, or `network`
/// when there was no response at all.
class ApiError implements Exception {
  const ApiError({required this.code, required this.message, this.status});

  final String code;
  final String message;
  final int? status;

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'ApiError($code, $status)';
}
