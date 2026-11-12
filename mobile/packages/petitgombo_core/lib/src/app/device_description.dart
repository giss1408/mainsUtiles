import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// What the server is told about this phone when it applies for enrolment.
class DeviceDescription {
  const DeviceDescription({required this.model, required this.platform});

  const DeviceDescription.unknown()
      : model = 'inconnu',
        platform = 'android';

  final String model;
  final String platform;

  /// Reads the model from the operating system.
  static Future<DeviceDescription> detect() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return DeviceDescription(model: info.utsname.machine, platform: 'ios');
      }
      final info = await plugin.androidInfo;
      return DeviceDescription(model: '${info.manufacturer} ${info.model}', platform: 'android');
    } catch (_) {
      return const DeviceDescription.unknown();
    }
  }
}
