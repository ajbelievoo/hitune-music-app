import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceHeaders {
  DeviceHeaders._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const Uuid _uuid = Uuid();

  static const String _kDeviceUuid = 'bof_device_uuid';
  static const String _kDeviceSerial = 'bof_device_serial';

  static Future<String> _getOrCreateId(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = _uuid.v4();
    await prefs.setString(key, created);
    return created;
  }

  static String _sanitizeVersion(String version) {
    final sanitized = version.replaceAll(RegExp(r'[^0-9\.]'), '');
    return sanitized.isEmpty ? '0' : sanitized;
  }

  static Future<Map<String, String>> build() async {
    final pkg = await PackageInfo.fromPlatform();

    String manufacturer = 'unknown';
    String model = 'unknown';
    String platform = Platform.operatingSystem.toLowerCase();
    String version = '0';

    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      manufacturer = (info.manufacturer).toLowerCase();
      model = (info.model).toLowerCase();
      version = (info.version.release).toLowerCase();
      platform = 'android';
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      manufacturer = 'apple';
      model = (info.utsname.machine).toLowerCase();
      version = (info.systemVersion).toLowerCase();
      platform = 'ios';
    } else if (Platform.isWindows) {
      final info = await _deviceInfo.windowsInfo;
      manufacturer = 'microsoft';
      model = (info.computerName).toLowerCase();
      version = (info.displayVersion).toLowerCase();
      platform = 'windows';
    } else if (Platform.isMacOS) {
      final info = await _deviceInfo.macOsInfo;
      manufacturer = 'apple';
      model = (info.model).toLowerCase();
      version = (info.osRelease).toLowerCase();
      platform = 'macos';
    } else if (Platform.isLinux) {
      final info = await _deviceInfo.linuxInfo;
      manufacturer = (info.id).toLowerCase();
      model = (info.name).toLowerCase();
      version = (info.versionId ?? '0').toLowerCase();
      platform = 'linux';
    }

    final deviceUuid = await _getOrCreateId(_kDeviceUuid);
    final deviceSerial = await _getOrCreateId(_kDeviceSerial);

    return {
      'x-bof-device-cordova': '0',
      'x-bof-device-is-virtual': 'false',
      'x-bof-device-manufacturer': manufacturer,
      'x-bof-device-model': model,
      'x-bof-device-platform': platform,
      'x-bof-device-version': _sanitizeVersion(version),
      'x-bof-device-uuid': deviceUuid,
      'x-bof-device-serial': deviceSerial,
      'x-bof-app-package': pkg.packageName,
      'x-bof-app-version': pkg.version,
      'x-bof-app-build': pkg.buildNumber,
    };
  }
}
