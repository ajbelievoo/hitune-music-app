import 'package:flutter/material.dart';

class AppConfig {
  static const String apiBaseUrl = 'https://music.hitune.in/api/';

  static const String requestCode = 'BusyOwlFrameWorkVersion201';
  static const String platform = 'web';
  static const int bofVersion = 2074;

  /// Configure via --dart-define=HITUNE_SIGN_KEY=... or --dart-define-from-file=.env
  static const String signKey = String.fromEnvironment('HITUNE_SIGN_KEY');

  /// Configure via --dart-define=HITUNE_ADMIN_SIGN_KEY=... or --dart-define-from-file=.env
  static const String adminSignKey = String.fromEnvironment('HITUNE_ADMIN_SIGN_KEY');

  static const bool enableAdminMode = bool.fromEnvironment('HITUNE_ADMIN_MODE', defaultValue: false);

  static const bool enableApiLogs = bool.fromEnvironment('HITUNE_API_LOGS', defaultValue: false);

  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF03DAC6);
}
