import 'package:flutter/foundation.dart';

/// Central logger that only emits output in debug mode.
/// Use [AppLogger.d] for debug, [AppLogger.e] for errors, [AppLogger.w] for warnings.
class AppLogger {
  AppLogger._();

  /// Release builds stay silent unless launched with
  /// `--dart-define=HITUNE_RELEASE_LOGS=true` — used for field debugging.
  static const bool _releaseLogging =
      bool.fromEnvironment('HITUNE_RELEASE_LOGS');

  static void _log(String level, String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode && !_releaseLogging) return;
    final output = '[$level] $message';
    if (error != null) {
      debugPrint(output);
      debugPrint('Error: $error');
      if (stack != null) debugPrint('Stack: $stack');
    } else {
      debugPrint(output);
    }
  }

  static void d(String message) => _log('D', message);
  static void w(String message, [Object? error]) => _log('W', message, error);
  static void e(String message, [Object? error, StackTrace? stack]) => _log('E', message, error, stack);
}
