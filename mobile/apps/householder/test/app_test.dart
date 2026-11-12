import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo/main.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

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
}
