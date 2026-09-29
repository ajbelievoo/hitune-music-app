import 'dart:convert';

import '../../../core/storage/secure_storage.dart';
import 'user_role.dart';

class UserContext {
  final UserRole role;
  final List<String> roleIds;
  final Map<String, dynamic> access;

  const UserContext({
    required this.role,
    required this.roleIds,
    required this.access,
  });

  static Future<UserContext> load() async {
    final roleStr = await SecureStore.getUserRole();
    final role = UserRole.fromBackend(roleStr);

    final roleIdsStr = await SecureStore.getUserRoleIds();
    final roleIds = (roleIdsStr ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final accessJson = await SecureStore.getUserRoleAccessJson();
    Map<String, dynamic> access = const {};
    if (accessJson != null && accessJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(accessJson);
        if (decoded is Map) {
          access = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return UserContext(role: role, roleIds: roleIds, access: access);
  }

  bool get isAdmin => role == UserRole.admin;
  bool get isModerator => role == UserRole.moderator;

  bool get hasAnyAccess => access.isNotEmpty || roleIds.isNotEmpty;

  bool hasAccessFlag(String key) {
    final v = access[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'yes';
    return false;
  }

  bool get canSeeAnalytics {
    // Backend role map does not explicitly expose an "analytics" flag in the core role parser.
    // We allow analytics when the user can upload (typical artist/manager trait) or for admins.
    return isAdmin || hasAccessFlag('upload');
  }
}
