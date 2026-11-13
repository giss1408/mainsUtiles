import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_adapter.dart';
import 'support/verification_fixtures.dart';

class Harness {
  final adapter = FakeAdapter();
  final camera = FakePhotoCapture();
  final position = FakePositionReader();
  int signOuts = 0;
}

/// Shows the checklist screen; [first] is the checklist the server returns on load.
Future<Harness> pumpChecklist(WidgetTester tester, Map<String, dynamic> first) async {
  final h = Harness()..adapter.reply(200, first);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dioWith(h.adapter)),
        sessionProvider.overrideWithValue(SignedInSession()),
        photoCaptureProvider.overrideWithValue(h.camera),
        positionReaderProvider.overrideWithValue(h.position),
        appRoleProvider.overrideWithValue(AppRole.householder),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: ChecklistScreen(onSignOut: () => h.signOuts++),
      ),
    ),
  );
  await settle(tester);
  return h;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await settle(tester);
}

/// Goes through one capture step: take the photo, then accept it.
Future<void> takeAndUse(WidgetTester tester) async {
  await tapText(tester, 'Prendre la photo');
  await tapText(tester, 'Utiliser cette photo');
}

const submitted = {'status': 'submitted', 'reason': ''};

void main() {
  testWidgets('checklist shows three steps with Commencer for a new householder', (tester) async {
    await pumpChecklist(tester, checklistJson());
    expect(find.text('Vérification de votre compte'), findsOneWidget);
    expect(find.text('Trois étapes pour publier vos offres.'), findsOneWidget);
    expect(find.text("Pièce d'identité"), findsOneWidget);
    expect(find.text('Justificatif de domicile'), findsOneWidget);
    expect(find.text('Position du domicile'), findsOneWidget);
    expect(find.text('Commencer'), findsNWidgets(3));
    expect(find.text('Compte vérifié'), findsNothing);
  });

  testWidgets('each status shows its French text', (tester) async {
    await pumpChecklist(
      tester,
      checklistJson(
        identity: submitted,
        address: {
          'status': 'expired',
          'reason': '',
          'commune': 'Cocody',
          'quartier': 'Angré',
          'expires_at': null,
        },
        homeLocation: {'status': 'in_review', 'reason': ''},
      ),
    );
    expect(find.text('Envoyé. Nous vérifions sous 24 h.'), findsOneWidget);
    expect(find.text('Justificatif expiré. Envoyez-en un nouveau.'), findsOneWidget);
    expect(find.text('En cours de vérification.'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
    expect(find.text('Commencer'), findsNothing);
  });

  testWidgets('refused step shows the reason and Recommencer', (tester) async {
    await pumpChecklist(
      tester,
      checklistJson(identity: {'status': 'refused', 'reason': 'Photo floue, reprenez le recto.'}),
    );
    expect(find.text('Photo floue, reprenez le recto.'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
  });

  testWidgets('H1 shows Compte vérifié and no step can be started', (tester) async {
    const confirmed = {'status': 'confirmed', 'reason': ''};
    await pumpChecklist(
      tester,
      checklistJson(
        tier: 'H1',
        identity: confirmed,
        address: {...confirmed, 'commune': 'Cocody', 'quartier': 'Angré', 'expires_at': null},
        homeLocation: confirmed,
      ),
    );
    expect(find.text('Compte vérifié'), findsOneWidget);
    expect(find.text('Confirmé'), findsNWidgets(3));
    expect(find.text('Commencer'), findsNothing);
    expect(find.text('Trois étapes pour publier vos offres.'), findsNothing);
  });

  testWidgets('a failed load shows the message and Réessayer loads again', (tester) async {
    final h = Harness()..adapter.offline = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dioWith(h.adapter)),
          sessionProvider.overrideWithValue(SignedInSession()),
          photoCaptureProvider.overrideWithValue(h.camera),
          positionReaderProvider.overrideWithValue(h.position),
          appRoleProvider.overrideWithValue(AppRole.householder),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: ChecklistScreen(onSignOut: () {})),
      ),
    );
    await settle(tester);
    expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);

    h.adapter
      ..offline = false
      ..reply(200, checklistJson());
    await tapText(tester, 'Réessayer');
    expect(find.text('Commencer'), findsNWidgets(3));
  });

  testWidgets('Se déconnecter calls the app back', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    await tapText(tester, 'Se déconnecter');
    expect(h.signOuts, 1);
  });

  testWidgets('identity flow takes three photos then sends them', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    await tapText(tester, 'Commencer');
    expect(find.text('Quel document allez-vous utiliser ?'), findsOneWidget);
    await tapText(tester, 'Passeport');

    expect(find.text('Recto du document'), findsOneWidget);
    await takeAndUse(tester);
    expect(find.text('Verso du document'), findsOneWidget);
    await takeAndUse(tester);
    expect(find.text('Votre visage'), findsOneWidget);
    await takeAndUse(tester);
    expect(h.camera.asked, [PhotoKind.idFront, PhotoKind.idBack, PhotoKind.selfie]);

    expect(find.text('Vérifiez vos photos'), findsOneWidget);
    h.adapter.reply(201, checklistJson(identity: submitted));
    await tapText(tester, 'Envoyer');

    final request = h.adapter.requests.last;
    expect(request.path, '/api/v1/verification/identity');
    final form = request.data as FormData;
    expect(Map.fromEntries(form.fields)['document_type'], 'passport');
    expect(form.files.map((f) => f.key), ['front', 'back', 'selfie']);
    // Back on the checklist, with the new status.
    expect(find.text('Vérification de votre compte'), findsOneWidget);
    expect(find.text('Envoyé. Nous vérifions sous 24 h.'), findsOneWidget);
  });

  testWidgets('Reprendre takes the photo again', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    await tapText(tester, 'Commencer');
    await tapText(tester, "Carte nationale d'identité");
    await tapText(tester, 'Prendre la photo');
    await tapText(tester, 'Reprendre');
    expect(h.camera.asked, [PhotoKind.idFront, PhotoKind.idFront]);
    expect(find.text('Recto du document'), findsOneWidget);
    await tapText(tester, 'Utiliser cette photo');
    expect(find.text('Verso du document'), findsOneWidget);
  });

  testWidgets('backing out of the camera stays on the same step', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    h.camera.cancel = true;
    await tapText(tester, 'Commencer');
    await tapText(tester, 'Passeport');
    await tapText(tester, 'Prendre la photo');
    expect(find.text('Recto du document'), findsOneWidget);
    expect(find.text('Utiliser cette photo'), findsNothing);
  });

  testWidgets('camera permission denied explains and offers the settings', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    h.camera.failure = CaptureFailure.permissionDeniedForever;
    await tapText(tester, 'Commencer');
    await tapText(tester, 'Passeport');
    await tapText(tester, 'Prendre la photo');
    expect(find.text("Autorisez l'appareil photo pour continuer."), findsOneWidget);
    await tapText(tester, 'Ouvrir les réglages');
    expect(h.camera.settingsOpened, 1);
  });

  testWidgets('a failed send keeps the photos and offers Envoyer again', (tester) async {
    final h = await pumpChecklist(tester, checklistJson());
    await tapText(tester, 'Commencer');
    await tapText(tester, 'Passeport');
    for (var i = 0; i < 3; i++) {
      await takeAndUse(tester);
    }
    h.adapter.offline = true;
    await tapText(tester, 'Envoyer');
    expect(find.text('Pas de connexion. Vos photos sont gardées. Réessayez.'), findsOneWidget);
    expect(find.text('Vérifiez vos photos'), findsOneWidget);
    expect(h.camera.asked, hasLength(3));

    h.adapter
      ..offline = false
      ..reply(201, checklistJson(identity: submitted));
    await tapText(tester, 'Envoyer');
    expect((h.adapter.requests.last.data as FormData).files, hasLength(3));
    expect(find.text('Envoyé. Nous vérifions sous 24 h.'), findsOneWidget);
    expect(h.camera.asked, hasLength(3));
  });

  testWidgets('address form requires commune and quartier before sending', (tester) async {
    final h = await pumpChecklist(tester, checklistJson(identity: submitted));
    await tapText(tester, 'Commencer'); // the first startable step is now the address
    expect(find.text('Quel justificatif allez-vous utiliser ?'), findsOneWidget);
    expect(find.text('Le document doit être à votre nom et dater de moins de 3 mois.'),
        findsOneWidget);
    await tapText(tester, "Facture d'électricité");
    await takeAndUse(tester);
    expect(h.camera.asked, [PhotoKind.addressProof]);

    final before = h.adapter.requests.length;
    await tapText(tester, 'Envoyer');
    expect(find.text('Choisissez la commune.'), findsOneWidget);
    expect(find.text('Indiquez le quartier.'), findsOneWidget);
    expect(h.adapter.requests.length, before);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.text('Yopougon').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '  Niangon Nord ');
    h.adapter.reply(
      201,
      checklistJson(
        identity: submitted,
        address: {
          ...submitted,
          'commune': 'Yopougon',
          'quartier': 'Niangon Nord',
          'expires_at': null,
        },
      ),
    );
    await tapText(tester, 'Envoyer');

    final fields = Map.fromEntries((h.adapter.requests.last.data as FormData).fields);
    expect(fields['document_type'], 'facture_electricite');
    expect(fields['commune'], 'Yopougon');
    expect(fields['quartier'], 'Niangon Nord');
    expect(find.text('Envoyé. Nous vérifions sous 24 h.'), findsNWidgets(2));
  });

  testWidgets('home location records the position and returns to the checklist', (tester) async {
    final h = await pumpChecklist(
      tester,
      checklistJson(
        identity: submitted,
        address: {...submitted, 'commune': 'Cocody', 'quartier': 'Angré', 'expires_at': null},
      ),
    );
    await tapText(tester, 'Commencer');
    expect(find.text('Faites cette étape chez vous.'), findsOneWidget);
    h.adapter.reply(201, checklistJson(identity: submitted, homeLocation: submitted));
    await tapText(tester, 'Enregistrer ma position');
    expect(h.position.reads, 1);
    expect(h.adapter.requests.last.path, '/api/v1/verification/home-location');
    expect(find.text('Vérification de votre compte'), findsOneWidget);
  });

  testWidgets('home location denied forever offers Ouvrir les réglages', (tester) async {
    final h = await pumpChecklist(
      tester,
      checklistJson(
        identity: submitted,
        address: {...submitted, 'commune': 'Cocody', 'quartier': 'Angré', 'expires_at': null},
      ),
    );
    h.position.failure = CaptureFailure.permissionDeniedForever;
    await tapText(tester, 'Commencer');
    final before = h.adapter.requests.length;
    await tapText(tester, 'Enregistrer ma position');
    expect(find.text('Autorisez la localisation pour continuer.'), findsOneWidget);
    expect(h.adapter.requests.length, before);
    await tapText(tester, 'Ouvrir les réglages');
    expect(h.position.settingsOpened, 1);
  });

  testWidgets('small phone with large text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final h = await pumpChecklist(
      tester,
      checklistJson(
        identity: {'status': 'refused', 'reason': 'Photo floue, reprenez le recto du document.'},
      ),
    );
    expect(tester.takeException(), isNull);

    // Identity: type list, capture, review, summary.
    await tapText(tester, 'Recommencer');
    expect(tester.takeException(), isNull);
    await tapText(tester, "Carte nationale d'identité");
    for (var i = 0; i < 3; i++) {
      await tapText(tester, 'Prendre la photo');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Utiliser cette photo');
    }
    expect(find.text('Vérifiez vos photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    h.adapter.reply(201, checklistJson(identity: submitted));
    await tapText(tester, 'Envoyer');

    // Address: type list, capture, form with errors.
    await tapText(tester, 'Commencer');
    await tapText(tester, "Facture d'eau");
    await takeAndUse(tester);
    await tapText(tester, 'Envoyer');
    expect(find.text('Choisissez la commune.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
