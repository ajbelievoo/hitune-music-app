import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _kAdminToken = 'admin_token';
  static const String _kUserToken = 'user_token';

  static const String _kUserSessId = 'user_sess_id';
  static const String _kUserSessKey = 'user_sess_key';
  static const String _kAdminSessId = 'admin_sess_id';
  static const String _kAdminSessKey = 'admin_sess_key';

  static const String _kUserRole = 'user_role';
  static const String _kUserRoleIds = 'user_role_ids';
  static const String _kUserRoleAccess = 'user_role_access';

  static const String _kUserId = 'user_id';
  static const String _kUserName = 'user_name';
  static const String _kUserAvatar = 'user_avatar';
  static const String _kUserCover = 'user_cover';

  static Future<void> setUserToken(String token) => _storage.write(key: _kUserToken, value: token);
  static Future<String?> getUserToken() => _storage.read(key: _kUserToken);
  static Future<void> clearUserToken() => _storage.delete(key: _kUserToken);

  static Future<void> setAdminToken(String token) => _storage.write(key: _kAdminToken, value: token);
  static Future<String?> getAdminToken() => _storage.read(key: _kAdminToken);
  static Future<void> clearAdminToken() => _storage.delete(key: _kAdminToken);

  static Future<void> setUserSession({required String sessId, required String sessKey}) async {
    await _storage.write(key: _kUserSessId, value: sessId);
    await _storage.write(key: _kUserSessKey, value: sessKey);
  }

  static Future<String?> getUserSessId() => _storage.read(key: _kUserSessId);
  static Future<String?> getUserSessKey() => _storage.read(key: _kUserSessKey);

  static Future<void> clearUserSession() async {
    await _storage.delete(key: _kUserSessId);
    await _storage.delete(key: _kUserSessKey);
  }

  static Future<void> setUserId(String userId) => _storage.write(key: _kUserId, value: userId);
  static Future<String?> getUserId() => _storage.read(key: _kUserId);
  static Future<void> clearUserId() => _storage.delete(key: _kUserId);

  static Future<void> setUserName(String name) => _storage.write(key: _kUserName, value: name);
  static Future<String?> getUserName() => _storage.read(key: _kUserName);
  static Future<void> clearUserName() => _storage.delete(key: _kUserName);

  static Future<void> setUserAvatar(String url) => _storage.write(key: _kUserAvatar, value: url);
  static Future<String?> getUserAvatar() => _storage.read(key: _kUserAvatar);
  static Future<void> clearUserAvatar() => _storage.delete(key: _kUserAvatar);

  static Future<void> setUserCover(String url) => _storage.write(key: _kUserCover, value: url);
  static Future<String?> getUserCover() => _storage.read(key: _kUserCover);
  static Future<void> clearUserCover() => _storage.delete(key: _kUserCover);

  static Future<void> setUserRole({required String role, String? roleIds, String? roleAccessJson}) async {
    await _storage.write(key: _kUserRole, value: role);
    if (roleIds != null) {
      await _storage.write(key: _kUserRoleIds, value: roleIds);
    }
    if (roleAccessJson != null) {
      await _storage.write(key: _kUserRoleAccess, value: roleAccessJson);
    }
  }

  static Future<String?> getUserRole() => _storage.read(key: _kUserRole);
  static Future<String?> getUserRoleIds() => _storage.read(key: _kUserRoleIds);
  static Future<String?> getUserRoleAccessJson() => _storage.read(key: _kUserRoleAccess);

  static Future<void> clearUserRole() async {
    await _storage.delete(key: _kUserRole);
    await _storage.delete(key: _kUserRoleIds);
    await _storage.delete(key: _kUserRoleAccess);
  }

  static Future<void> setAdminSession({required String sessId, required String sessKey}) async {
    await _storage.write(key: _kAdminSessId, value: sessId);
    await _storage.write(key: _kAdminSessKey, value: sessKey);
  }

  static Future<String?> getAdminSessId() => _storage.read(key: _kAdminSessId);
  static Future<String?> getAdminSessKey() => _storage.read(key: _kAdminSessKey);

  static Future<void> clearAdminSession() async {
    await _storage.delete(key: _kAdminSessId);
    await _storage.delete(key: _kAdminSessKey);
  }
}
