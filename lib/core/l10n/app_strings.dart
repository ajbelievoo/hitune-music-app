/// Minimal localization table. Extend entries incrementally - existing
/// screens keep English fallbacks so nothing breaks while translating.
class AppStrings {
  AppStrings._();

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'nav_listen_now': 'Listen Now',
      'nav_browse': 'Browse',
      'nav_radio': 'Radio',
      'nav_library': 'Library',
      'nav_search': 'Search',
      'downloads': 'Downloads',
      'notifications': 'Notifications',
      'settings': 'Settings',
      'queue': 'Queue',
      'lyrics': 'Lyrics',
      'sleep_timer': 'Sleep Timer',
      'offline_mode': 'You are offline. Only downloaded songs can be played.',
      'made_for_you': 'Made for you',
    },
    'hi': {
      'nav_listen_now': 'अभी सुनें',
      'nav_browse': 'ब्राउज़ करें',
      'nav_radio': 'रेडियो',
      'nav_library': 'लाइब्रेरी',
      'nav_search': 'खोजें',
      'downloads': 'डाउनलोड',
      'notifications': 'सूचनाएँ',
      'settings': 'सेटिंग्स',
      'queue': 'क्यू',
      'lyrics': 'गीत के बोल',
      'sleep_timer': 'स्लीप टाइमर',
      'offline_mode': 'आप ऑफ़लाइन हैं। सिर्फ़ डाउनलोड किए गए गाने चलेंगे।',
      'made_for_you': 'आपके लिए बनाया गया',
    },
  };

  static const supportedLocales = ['en', 'hi'];

  static String tr(String key, String languageCode) {
    return _values[languageCode]?[key] ?? _values['en']?[key] ?? key;
  }
}
