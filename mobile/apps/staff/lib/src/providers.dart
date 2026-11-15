import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:petitgombo_core/petitgombo_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ops_controller.dart';
import 'staff_api.dart';
import 'staff_controller.dart';
import 'staff_session.dart';

/// Opens a link in another app. Returns false when nothing can open it.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

final urlOpenerProvider = Provider<UrlOpener>((ref) => openExternally);

final staffApiProvider = Provider<StaffApi>((ref) => StaffApi(ref.watch(dioProvider)));

final staffSessionProvider = Provider<StaffSession>((ref) {
  final device = ref.watch(deviceDescriptionProvider);
  return StaffSession(
    ref.watch(staffApiProvider),
    ref.watch(deviceIdentityProvider),
    deviceModel: device.model,
    platform: device.platform,
  );
});

final staffControllerProvider = StateNotifierProvider<StaffController, StaffState>(
  (ref) => StaffController(
    api: ref.watch(staffApiProvider),
    session: ref.watch(staffSessionProvider),
  ),
);

final opsControllerProvider = StateNotifierProvider<OpsController, OpsState>(
  (ref) => OpsController(
    api: ref.watch(staffApiProvider),
    staff: ref.watch(staffControllerProvider.notifier),
  ),
);
