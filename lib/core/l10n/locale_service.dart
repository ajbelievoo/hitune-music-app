import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_strings.dart';

/// Holds the active UI language and translates keys via [AppStrings].
///
/// Wire into the app with a provider and call [t] wherever a localized
/// string is needed:
/// ```dart
/// L10n.of(context)  // or L10n.t('nav_home')
/// ```
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const String _prefsKey = 'app_language';
  String _languageCode = 'en';

  String get languageCode => _languageCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && AppStrings.supportedLocales.contains(raw)) {
      _languageCode = raw;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String code) async {
    if (!AppStrings.supportedLocales.contains(code)) return;
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
    notifyListeners();
  }
}

/// Shorthand accessor.
class L10n {
  L10n._();
  static String t(String key) => AppStrings.tr(key, LocaleService.instance.languageCode);
}
