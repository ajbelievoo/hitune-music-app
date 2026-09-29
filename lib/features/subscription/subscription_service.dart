import 'package:flutter/foundation.dart';

import '../config/client_config_service.dart';

/// Central catalog of feature keys used for plan gating.
///
/// Admins control which plan unlocks which feature by returning a
/// `plan_features` map from the `client_config` endpoint:
///
/// ```json
/// "plan_features": {
///   "free":    ["sleep_timer", "lyrics"],
///   "premium": ["offline_downloads", "hq_audio", "no_ads", "equalizer", "casting"]
/// }
/// ```
///
/// If the backend does not send `plan_features` yet, every feature is allowed
/// (fail-open) so existing users are not locked out.
class AppFeatures {
  AppFeatures._();

  static const String offlineDownloads = 'offline_downloads';
  static const String lyrics = 'lyrics';
  static const String sleepTimer = 'sleep_timer';
  static const String equalizer = 'equalizer';
  static const String soundControls = 'sound_controls';
  static const String hqAudio = 'hq_audio';
  static const String noAds = 'no_ads';
  static const String casting = 'casting';
  static const String unlimitedSkips = 'unlimited_skips';
  static const String comments = 'comments';
  static const String playlists = 'playlists';
  static const String recommendations = 'recommendations';
  static const String pushNotifications = 'push_notifications';
  static const String voiceSearch = 'voice_search';
  static const String collaborativePlaylists = 'collaborative_playlists';

  static const List<String> all = [
    offlineDownloads,
    lyrics,
    sleepTimer,
    equalizer,
    soundControls,
    hqAudio,
    noAds,
    casting,
    unlimitedSkips,
    comments,
    playlists,
    recommendations,
    pushNotifications,
    voiceSearch,
    collaborativePlaylists,
  ];

  static const Map<String, String> labels = {
    offlineDownloads: 'Offline Downloads',
    lyrics: 'Lyrics',
    sleepTimer: 'Sleep Timer',
    equalizer: 'Equalizer',
    soundControls: 'Speed / Pitch Controls',
    hqAudio: 'High Quality Audio',
    noAds: 'Ad-Free Listening',
    casting: 'Chromecast / AirPlay',
    unlimitedSkips: 'Unlimited Skips',
    comments: 'Comments',
    playlists: 'Playlists',
    recommendations: 'Personalized Recommendations',
    pushNotifications: 'Push Notifications',
    voiceSearch: 'Voice Search',
    collaborativePlaylists: 'Collaborative Playlists',
  };
}

/// Reads the user's current plan and allowed features from the client config.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  String _plan = 'free';
  Set<String>? _features; // null => not configured by backend (fail-open)

  String get currentPlan => _plan;
  bool get isPaid => _plan != 'free';

  /// Refresh cached values from the latest client config. Call this after
  /// [ClientConfigService.fetchClientConfig] completes.
  void refresh() {
    final config = ClientConfigService().config;
    if (config == null) return;

    final newPlan = _detectPlan(config);
    final newFeatures = _resolveFeatures(config, newPlan);

    if (newPlan != _plan || !setEquals(newFeatures, _features)) {
      _plan = newPlan;
      _features = newFeatures;
      notifyListeners();
    }
  }

  /// True when [feature] is available to the current plan.
  bool hasFeature(String feature) {
    final features = _features;
    if (features == null) {
      // Backend has not configured plan_features yet - allow everything.
      refresh();
      return _features == null || _features!.contains(feature);
    }
    return features.contains(feature);
  }

  /// True when the backend has configured plan gating at all.
  bool get isConfigured => _features != null;

  List<String> get enabledFeatures =>
      _features == null ? List<String>.from(AppFeatures.all) : _features!.toList();

  String _detectPlan(Map<String, dynamic> config) {
    final user = config['user'];
    if (user is Map) {
      const keys = ['plan', 'plan_id', 'plan_name', 'membership', 'subscription_plan'];
      for (final k in keys) {
        final direct = user[k];
        final fromData = user['data'] is Map ? (user['data'] as Map)[k] : null;
        final fromExtra = user['extra'] is Map ? (user['extra'] as Map)[k] : null;
        final v = (direct ?? fromData ?? fromExtra)?.toString();
        if (v != null && v.isNotEmpty) return v.toLowerCase();
      }
      final premium = user['is_premium'] ?? user['premium'];
      if (premium == true || premium == 1 || premium == '1') return 'premium';
    }
    final setting = config['setting'];
    if (setting is Map) {
      final d = setting['default_plan']?.toString();
      if (d != null && d.isNotEmpty) return d.toLowerCase();
    }
    return 'free';
  }

  Set<String>? _resolveFeatures(Map<String, dynamic> config, String plan) {
    final raw = config['plan_features'] ?? (config['setting'] is Map ? (config['setting'] as Map)['plan_features'] : null);
    if (raw is! Map) return null;

    Object? planEntry = raw[plan] ?? raw['default'];
    if (planEntry == null && plan != 'free') planEntry = raw['free'];

    if (planEntry is List) {
      return planEntry.map((e) => e.toString()).toSet();
    }
    if (planEntry is Map) {
      return planEntry.entries
          .where((e) => e.value == true || e.value == 1 || e.value == '1' || e.value == 'true')
          .map((e) => e.key.toString())
          .toSet();
    }
    return null;
  }
}
