import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobber/device_capture.dart';
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

  testWidgets('the jobber app takes verification photos with the in-app camera', (tester) async {
    await tester.pumpWidget(
      buildApp(overrides: [keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore())]),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
    expect(container.read(photoCaptureProvider), isA<CameraPhotoCapture>());
  });
}
