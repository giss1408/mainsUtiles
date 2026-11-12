import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

/// The householder app. Everything it shows lives in petitgombo_core.
PetitGomboApp buildApp({
  DeviceDescription device = const DeviceDescription.unknown(),
  List<Override> overrides = const [],
}) =>
    PetitGomboApp(role: AppRole.householder, device: device, overrides: overrides);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp(device: await DeviceDescription.detect()));
}
