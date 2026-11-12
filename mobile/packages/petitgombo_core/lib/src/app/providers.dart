import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/device_identity.dart';
import '../auth/key_value_store.dart';
import '../auth/session.dart';
import '../enrolment/enrolment_controller.dart';
import '../enrolment/enrolment_state.dart';
import 'app_role.dart';
import 'device_description.dart';

/// Set by [PetitGomboApp]; which app is running.
final appRoleProvider = Provider<AppRole>((ref) => throw UnimplementedError('appRoleProvider'));

/// Set by [PetitGomboApp]; the phone's model and platform.
final deviceDescriptionProvider =
    Provider<DeviceDescription>((ref) => const DeviceDescription.unknown());

final keyValueStoreProvider = Provider<KeyValueStore>((ref) => SecureKeyValueStore());

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  ),
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

final deviceIdentityProvider =
    Provider<DeviceIdentity>((ref) => DeviceIdentity(ref.watch(keyValueStoreProvider)));

final sessionProvider = Provider<Session>(
  (ref) => Session(
    ref.watch(apiClientProvider),
    ref.watch(deviceIdentityProvider),
    ref.watch(keyValueStoreProvider),
  ),
);

final enrolmentControllerProvider =
    StateNotifierProvider<EnrolmentController, EnrolmentState>((ref) {
  final device = ref.watch(deviceDescriptionProvider);
  return EnrolmentController(
    api: ref.watch(apiClientProvider),
    identity: ref.watch(deviceIdentityProvider),
    session: ref.watch(sessionProvider),
    store: ref.watch(keyValueStoreProvider),
    role: ref.watch(appRoleProvider),
    deviceModel: device.model,
    platform: device.platform,
  );
});
