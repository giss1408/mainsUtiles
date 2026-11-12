import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

class FakeSession implements Session {
  FakeSession({this.restored, this.offline = false});

  Me? restored;
  bool offline;
  int signOuts = 0;
  int signIns = 0;

  @override
  Future<Me?> restore() async {
    if (offline) throw const ApiError(code: 'network', message: '');
    return restored;
  }

  @override
  Future<Me> signIn() async {
    signIns++;
    return const Me(id: 'u-1', phone: '+2250708091011', role: 'jobber');
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  String? get access => null;

  @override
  Future<T> authorized<T>(Future<T> Function(String access) call) => call('fake-access');
}

const me = Me(id: 'u-1', phone: '+2250708091011', role: 'jobber');

Future<void> pumpApp(
  WidgetTester tester,
  AppRole role,
  FakeSession session, {
  List<Override> extra = const [],
}) async {
  await tester.pumpWidget(
    PetitGomboApp(
      role: role,
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        sessionProvider.overrideWithValue(session),
        ...extra,
      ],
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('without a session the app opens on the phone screen', (tester) async {
    await pumpApp(tester, AppRole.jobber, FakeSession());
    expect(find.text('Ton numéro de téléphone'), findsOneWidget);
  });

  testWidgets('a restored session opens the home placeholder with the role label', (tester) async {
    await pumpApp(tester, AppRole.jobber, FakeSession(restored: me));
    expect(find.text('Bienvenue'), findsOneWidget);
    expect(find.text('Mini-jobber'), findsOneWidget);
  });

  testWidgets('a signed-in householder lands on the verification checklist', (tester) async {
    final adapter = FakeAdapter()..reply(200, checklistJson());
    await pumpApp(
      tester,
      AppRole.householder,
      FakeSession(restored: me),
      extra: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        photoCaptureProvider.overrideWithValue(FakePhotoCapture()),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
      ],
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Vérification de votre compte'), findsOneWidget);
    expect(find.text('Commencer'), findsNWidgets(3));
    expect(find.text('Bienvenue'), findsNothing);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer fake-access');
  });

  testWidgets('a verified householder lands on Mes offres', (tester) async {
    final adapter = FakeAdapter()
      ..reply(200, checklistJson(tier: 'H1'))
      ..reply(200, {'can_publish': true, 'review_hours': 24, 'offers': []})
      ..reply(200, {
        'categories': [
          {
            'id': 1,
            'name': 'Ménage',
            'duties': ['Dépoussiérer'],
            'durations_minutes': [180],
            'suggested_pay_min': 2000,
            'suggested_pay_max': 5000,
          }
        ],
        'limits': {
          'earliest_start': '06:00',
          'latest_end': '19:00',
          'min_pay': 1000,
          'max_pay': 100000,
          'max_days_ahead': 30,
          'note_max_length': 300,
        },
      });
    await pumpApp(
      tester,
      AppRole.householder,
      FakeSession(restored: me),
      extra: [
        dioProvider.overrideWithValue(dioWith(adapter)),
        photoCaptureProvider.overrideWithValue(FakePhotoCapture()),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Mes offres'), findsOneWidget);
    expect(find.text('Créer une offre'), findsOneWidget);
    expect(find.text('Vérification de votre compte'), findsNothing);
  });

  testWidgets('signing out shows the reconnect screen, and reconnecting returns home',
      (tester) async {
    final session = FakeSession(restored: me);
    await pumpApp(tester, AppRole.jobber, session);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump();
    await tester.pump();
    expect(session.signOuts, 1);
    expect(find.text('Se reconnecter'), findsOneWidget);
    expect(find.text('Bienvenue'), findsNothing);

    await tester.tap(find.text('Se reconnecter'));
    await tester.pump();
    await tester.pump();
    expect(session.signIns, 1);
    expect(find.text('Bienvenue'), findsOneWidget);
  });

  testWidgets('no connection at start shows a retry screen', (tester) async {
    final session = FakeSession(offline: true);
    await pumpApp(tester, AppRole.jobber, session);
    expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
    session.offline = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ton numéro de téléphone'), findsOneWidget);
  });
}
