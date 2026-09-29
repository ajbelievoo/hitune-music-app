import 'package:flutter/material.dart';

import '../../core/storage/secure_storage.dart';
import 'auth_bottom_sheet.dart';

class AuthGate {
  static Future<bool> isLoggedIn() async {
    final key = await SecureStore.getUserSessKey();
    final id = await SecureStore.getUserSessId();
    if (key == null || key.isEmpty) return false;
    if (id == null || id.isEmpty) return false;
    return true;
  }

  static Future<bool> ensureLoggedIn(
    BuildContext context, {
    String? reason,
  }) async {
    final ok = await isLoggedIn();
    if (ok) return true;

    if (!context.mounted) return false;

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => AuthBottomSheet(reason: reason),
    );

    if (!context.mounted) return false;

    return res == true;
  }
}
