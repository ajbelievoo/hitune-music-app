import 'package:flutter/foundation.dart';

/// Service to broadcast authentication state changes to all listeners.
/// Use this to notify the app when login/logout occurs.
class AuthStateService extends ChangeNotifier {
  static final AuthStateService _instance = AuthStateService._internal();
  factory AuthStateService() => _instance;
  AuthStateService._internal();

  bool _isLoggedIn = false;
  String? _lastError;

  bool get isLoggedIn => _isLoggedIn;

  /// Last social-login failure reported via deep link (one-shot).
  String? get lastError => _lastError;

  /// Returns and clears the last error so it is shown only once.
  String? takeLastError() {
    final e = _lastError;
    _lastError = null;
    return e;
  }

  /// Call this after successful login to notify all listeners
  void notifyLoggedIn() {
    _isLoggedIn = true;
    _lastError = null;
    debugPrint('[AUTH_STATE] notifyLoggedIn called');
    notifyListeners();
  }

  /// Call this when social login fails (e.g. backend deep link with
  /// success=false&error=...) so open login UI can show the message.
  void notifyLoginFailed(String message) {
    _isLoggedIn = false;
    _lastError = message;
    debugPrint('[AUTH_STATE] notifyLoginFailed: $message');
    notifyListeners();
  }

  /// Call this after logout to notify all listeners  
  void notifyLoggedOut() {
    _isLoggedIn = false;
    debugPrint('[AUTH_STATE] notifyLoggedOut called');
    notifyListeners();
  }
}
