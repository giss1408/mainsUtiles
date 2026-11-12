import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

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

Future<void> pumpApp(WidgetTester tester, AppRole role, FakeSession session) async {
  await tester.pumpWidget(
    PetitGomboApp(
      role: role,
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        sessionProvider.overrideWithValue(session),
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

  testWidgets('the householder home shows Particulier', (tester) async {
    await pumpApp(tester, AppRole.householder, FakeSession(restored: me));
    expect(find.text('Particulier'), findsOneWidget);
    expect(find.text('Mini-jobber'), findsNothing);
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
