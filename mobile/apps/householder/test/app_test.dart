import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo/main.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

/// Answers every request with the same JSON body.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.body);

  final Map<String, dynamic> body;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SignedIn implements Session {
  static const _me = Me(id: 'u-1', phone: '+2250505050505', role: 'householder');

  @override
  String? get access => 'acc';

  @override
  Future<T> authorized<T>(Future<T> Function(String access) call) => call('acc');

  @override
  Future<Me?> restore() async => _me;

  @override
  Future<Me> signIn() async => _me;

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('the householder app opens on the phone screen in the vous form', (tester) async {
    await tester.pumpWidget(
      buildApp(overrides: [keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore())]),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
    expect(find.text('Ton numéro de téléphone'), findsNothing);
    expect(find.text('Mini-jobber'), findsNothing);
  });

  testWidgets('a signed-in householder lands on the verification checklist', (tester) async {
    const step = {'status': 'not_started', 'reason': ''};
    final adapter = _FixedAdapter({
      'tier': 'H0',
      'review_hours': 24,
      'communes': ['Cocody'],
      'identity': step,
      'address': {...step, 'commune': '', 'quartier': '', 'expires_at': null},
      'home_location': step,
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
    await tester.pumpWidget(
      buildApp(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          sessionProvider.overrideWithValue(_SignedIn()),
          dioProvider.overrideWithValue(dio),
        ],
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Vérification de votre compte'), findsOneWidget);
    expect(find.text('Commencer'), findsNWidgets(3));
    expect(adapter.paths, ['/api/v1/verification']);
  });
}
