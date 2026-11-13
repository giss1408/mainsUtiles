import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Captures requests and answers from a queue, without any network.
class FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<(int, Object?)> replies = [];
  bool offline = false;

  /// Behave as offline once the queued replies are used up.
  bool offlineAfterReplies = false;

  void reply(int status, Object? body) => replies.add((status, body));

  /// Answers with raw bytes (an image), not JSON.
  void replyBytes(int status, List<int> bytes) => replies.add((status, Uint8List.fromList(bytes)));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline || (offlineAfterReplies && replies.isEmpty)) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final (status, body) = replies.removeAt(0);
    if (body is Uint8List) {
      return ResponseBody.fromBytes(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio dioWith(FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.httpClientAdapter = adapter;
  return dio;
}
