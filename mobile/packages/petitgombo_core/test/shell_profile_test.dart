import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

class Harness {
  int signOuts = 0;
}

Future<Harness> pumpShell(
  WidgetTester tester, {
  AppRole role = AppRole.jobber,
  Size? size,
  double textScale = 1,
}) async {
  final h = Harness();
  if (size != null) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appRoleProvider.overrideWithValue(role),
        dioProvider.overrideWithValue(dioWith(FakeAdapter()..offline = true)),
        sessionProvider.overrideWithValue(SignedInSession()),
        positionReaderProvider.overrideWithValue(FakePositionReader()),
        photoCaptureProvider.overrideWithValue(FakePhotoCapture()),
        meProvider.overrideWith(
          (ref) async => const Me(id: 'u-1', phone: '+2250708091011', role: 'jobber'),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: HomeShell(onSignOut: () => h.signOuts++, home: const Text('contenu')),
      ),
    ),
  );
  await settle(tester);
  return h;
}

void main() {
  test('a phone number is masked except its first and last two digits', () {
    expect(maskPhone('+2250708091011'), '+225 07 •• •• •• 11');
  });

  testWidgets('the shell shows the header, the home tab and the footer bar', (tester) async {
    await pumpShell(tester);
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.text('contenu'), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('the profile shows the role, the masked phone and never the full number',
      (tester) async {
    await pumpShell(tester);
    await tap(tester, find.text('Profil'));
    expect(find.text('Mini-jobber'), findsOneWidget);
    expect(find.text('+225 07 •• •• •• 11'), findsOneWidget);
    expect(find.textContaining('0708091011'), findsNothing);
    expect(find.text('Confidentialité et données'), findsOneWidget);
    expect(find.text("Conditions d'utilisation"), findsOneWidget);
    expect(find.text('Vérification du compte'), findsNothing); // householders only
  });

  testWidgets('a householder profile has the verification row', (tester) async {
    await pumpShell(tester, role: AppRole.householder);
    await tap(tester, find.text('Profil'));
    expect(find.text('Ménage'), findsOneWidget);
    expect(find.text('Vérification du compte'), findsOneWidget);
    expect(find.text('À compléter'), findsOneWidget);
  });

  testWidgets('the privacy notice opens from the profile and says it is a draft', (tester) async {
    await pumpShell(tester);
    await tap(tester, find.text('Profil'));
    await tap(tester, find.text('Confidentialité et données'));
    expect(find.text('Ce que nous collectons'), findsOneWidget);
    expect(find.text('Qui peut les voir'), findsOneWidget);
    expect(find.textContaining('à faire valider par un juriste'), findsOneWidget);
  });

  test('a rating is written with a comma, and says so when there is no review', () {
    expect(StarRating.label(4.5, 12), '4,5 sur 5 · 12 avis');
    expect(StarRating.label(0, 0), "Pas encore d'avis");
  });

  testWidgets('the profile shows trust badges and no invented rating', (tester) async {
    await pumpShell(tester);
    await tap(tester, find.text('Profil'));
    expect(find.text('Téléphone confirmé'), findsOneWidget);
    expect(find.text("Pas encore d'avis"), findsOneWidget);
    await tap(tester, find.text('Avis reçus'));
    expect(find.text('Aucun avis pour le moment'), findsOneWidget);
    expect(find.byType(ReviewCard), findsNothing);
  });

  testWidgets('a review card shows the author, the words and its stars in words', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ReviewCard(author: 'Awa', stars: 4, when: 'nov. 2026', text: 'Très ponctuelle.'),
        ),
      ),
    );
    expect(find.text('Awa'), findsOneWidget);
    expect(find.text('Très ponctuelle.'), findsOneWidget);
    expect(find.bySemanticsLabel('4 sur 5'), findsOneWidget);
  });

  testWidgets('Se déconnecter in the profile signs out', (tester) async {
    final h = await pumpShell(tester);
    await tap(tester, find.text('Profil'));
    await tap(tester, find.text('Se déconnecter'));
    expect(h.signOuts, 1);
  });

  testWidgets('the help button in the header opens Comment ça marche', (tester) async {
    await pumpShell(tester);
    await tap(tester, find.byIcon(Icons.help_outline));
    expect(find.text('Comment ça marche'), findsOneWidget);
    expect(find.text('2. Consulte les offres'), findsOneWidget);
  });

  testWidgets('profile and privacy do not overflow on a 320dp phone at twice the text size',
      (tester) async {
    await pumpShell(tester, size: const Size(320, 640), textScale: 2);
    await tap(tester, find.text('Profil'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Confidentialité et données'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a flow step shows its position', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const FlowScaffold(title: 'Titre', step: 2, steps: 6, children: []),
      ),
    );
    expect(find.text('Étape 2 sur 6'), findsOneWidget);
  });

  testWidgets('the footer links open the privacy notice before sign-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: LegalFooter())),
    );
    await tap(tester, find.text('Confidentialité'));
    expect(find.text('Confidentialité et données'), findsOneWidget);
  });
}
