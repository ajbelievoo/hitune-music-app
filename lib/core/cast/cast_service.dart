import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Chromecast / AirPlay availability facade.
///
/// Real casting needs the native Google Cast SDK (Android: `cast.framework`,
/// iOS: `google-cast-sdk`). The Flutter package options (`flutter_cast_video`,
/// `cast`) require native setup which is documented in
/// docs/BACKEND_REQUIREMENTS.md. Until the native side is wired, [isAvailable]
/// reports false and UI should hide the cast button.
class CastService {
  CastService._();
  static final CastService instance = CastService._();

  bool _initialized = false;
  bool _available = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Only Android/iOS can cast. The native SDK is not bundled yet, so we
    // conservatively report unavailable. Flip to true after integrating the
    // Cast SDK (see docs).
    _available = false;
  }

  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS) && _available;

  /// Human readable reason when casting is unavailable.
  String get unavailableReason => 'Casting is not set up in this build yet.';
}
