import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/fake_controller.dart';

Future<FakeEnrolmentController> pumpWith(
  WidgetTester tester,
  EnrolmentState state, {
  AppRole role = AppRole.householder,
}) async {
  final controller = FakeEnrolmentController(state);
  await tester.pumpWidget(
    ProviderScope(
      // A new key each time, so a second call in one test really shows the new state.
      key: UniqueKey(),
      overrides: [
        appRoleProvider.overrideWithValue(role),
        enrolmentControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const EnrolmentFlow()),
    ),
  );
  return controller;
}

void main() {
  testWidgets('initial state shows the phone screen with the WhatsApp note', (tester) async {
    await pumpWith(tester, const EnrolmentInitial());
    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
    expect(find.text('Nous vous enverrons un numéro de confirmation par WhatsApp.'), findsOneWidget);
    expect(find.text('+225'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('the jobber app speaks in tu', (tester) async {
    await pumpWith(tester, const EnrolmentInitial(), role: AppRole.jobber);
    expect(find.text('Ton numéro de téléphone'), findsOneWidget);
    expect(find.text("On t'envoie un numéro de confirmation par WhatsApp."), findsOneWidget);
    expect(find.text('Votre numéro de téléphone'), findsNothing);
  });

  testWidgets('Continuer sends the typed number to submitPhone', (tester) async {
    final controller = await pumpWith(tester, const EnrolmentInitial());
    await tester.enterText(find.byType(TextField), '0708091011');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    expect(controller.submittedPhone, '0708091011');
  });

  testWidgets('pending shows the response time and Actualiser refreshes', (tester) async {
    final controller = await pumpWith(tester, const EnrolmentPending(24));
    expect(find.text('Demande reçue'), findsOneWidget);
    expect(find.text('Confirmation par WhatsApp sous 24 h.'), findsOneWidget);
    await tester.tap(find.text('Actualiser'));
    await tester.pump();
    expect(controller.refreshes, 1);
  });

  testWidgets('held shows the verification message and the reason', (tester) async {
    await pumpWith(tester, const EnrolmentHeld('Numéro à confirmer'));
    expect(find.text('Votre demande est en cours de vérification.'), findsOneWidget);
    expect(find.text('Numéro à confirmer'), findsOneWidget);
  });

  testWidgets('awaiting code shows the server error under the field', (tester) async {
    await pumpWith(
      tester,
      const EnrolmentAwaitingCode(errorMessage: 'Numéro de confirmation incorrect.'),
    );
    expect(find.text('Numéro de confirmation'), findsOneWidget);
    expect(find.text('Numéro de confirmation incorrect.'), findsOneWidget);
    expect(find.text('Notre équipe ne vous demandera jamais ce numéro.'), findsOneWidget);
  });

  testWidgets('Valider is disabled until six digits are entered', (tester) async {
    final controller = await pumpWith(tester, const EnrolmentAwaitingCode());
    final button = find.widgetWithText(FilledButton, 'Valider');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(controller.submittedCode, '123456');
  });

  testWidgets('locked shows Nouvelle demande and calls startOver', (tester) async {
    final controller = await pumpWith(tester, const EnrolmentLocked());
    expect(find.text("Trop d'essais. Faites une nouvelle demande."), findsOneWidget);
    await tester.tap(find.text('Nouvelle demande'));
    await tester.pump();
    expect(controller.startOvers, 1);
  });

  testWidgets('refused shows the reason and expired its message', (tester) async {
    await pumpWith(tester, const EnrolmentRefused('Numéro injoignable'));
    expect(find.text('Demande refusée'), findsOneWidget);
    expect(find.text('Numéro injoignable'), findsOneWidget);

    await pumpWith(tester, const EnrolmentExpired());
    expect(find.text('Votre demande a expiré.'), findsOneWidget);
  });

  testWidgets('failure keeps the typed phone number and shows the message', (tester) async {
    final controller = await pumpWith(tester, const EnrolmentInitial());
    await tester.enterText(find.byType(TextField), '0708');
    controller.state = const EnrolmentFailure(
      'Pas de connexion. Réessayez.',
      previous: EnrolmentInitial(),
    );
    await tester.pump();
    expect(find.text('Pas de connexion. Réessayez.'), findsOneWidget);
    expect(find.text('0708'), findsOneWidget);
    expect(find.text('Votre numéro de téléphone'), findsOneWidget);
  });

  testWidgets('every screen fits a 320dp wide phone at double text size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const states = <EnrolmentState>[
      EnrolmentInitial(),
      EnrolmentSubmitting(),
      EnrolmentPending(24),
      EnrolmentHeld('Numéro à confirmer avant de continuer'),
      EnrolmentAwaitingCode(errorMessage: 'Ce numéro a été remplacé. Utilisez le dernier message WhatsApp reçu.'),
      EnrolmentRefused('Numéro injoignable après plusieurs essais'),
      EnrolmentLocked(),
      EnrolmentExpired(),
      EnrolmentFailure('Pas de connexion. Réessayez.', previous: EnrolmentAwaitingCode()),
    ];
    for (final state in states) {
      await pumpWith(tester, state, role: AppRole.jobber);
      expect(tester.takeException(), isNull, reason: state.runtimeType.toString());
    }
  });
}
