import 'package:flutter_test/flutter_test.dart';
import 'package:jobber/main.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

void main() {
  testWidgets('the jobber app opens on the phone screen in the tu form', (tester) async {
    await tester.pumpWidget(
      buildApp(overrides: [keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore())]),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ton numéro de téléphone'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });
}
