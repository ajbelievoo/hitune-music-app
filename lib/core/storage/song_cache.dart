import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache entry with expiration
class _CacheEntry {
  final String data;
  final DateTime expiresAt;

  _CacheEntry({required this.data, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'data': data,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
    data: json['data'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
  );
}

/// Local cache service for song URLs and other API responses
/// Default expiration: 8 hours (YouTube/googlevideo URLs cap at their own
/// `expire` timestamp so we never hand out a dead link).
class SongCacheService {
  SongCacheService._();
  static final SongCacheService instance = SongCacheService._();

  static const Duration _defaultExpiry = Duration(hours: 8);
  // v2 — v1 entries predated stream validation and hold dead
  // googlevideo links that return 403/404 on play.
  static const String _prefsKey = 'song_url_cache_v2';
  static const String _legacyPrefsKey = 'song_url_cache_v1';

  Map<String, _CacheEntry> _memoryCache = {};
  bool _loaded = false;

  /// Load cache from persistent storage
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPrefsKey);
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _memoryCache = decoded.map((key, value) {
        try {
          return MapEntry(key, _CacheEntry.fromJson(value as Map<String, dynamic>));
        } catch (_) {
          return MapEntry(key, _CacheEntry(data: '', expiresAt: DateTime.now().subtract(const Duration(days: 1))));
        }
      });
      // Remove expired entries
      _memoryCache.removeWhere((key, entry) => entry.isExpired);
    } catch (_) {
      _memoryCache = {};
    }
  }

  /// Save cache to persistent storage
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = _memoryCache.map((key, entry) => MapEntry(key, entry.toJson()));
    await prefs.setString(_prefsKey, json.encode(jsonData));
  }

  /// Generate cache key for a song
  String _makeKey(String objectHash, String objectType, {String? quality}) {
    return '${objectType}_$objectHash${quality != null ? '_$quality' : ''}';
  }

  /// Get cached song URL if available and not expired
  Future<Map<String, dynamic>?> getSongUrl(
    String objectHash,
    String objectType, {
    String? quality,
  }) async {
    await _ensureLoaded();

    final key = _makeKey(objectHash, objectType, quality: quality);
    final entry = _memoryCache[key];

    if (entry == null || entry.isExpired) {
      if (entry != null && entry.isExpired) {
        _memoryCache.remove(key);
        await _persist();
      }
      return null;
    }

    try {
      return json.decode(entry.data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Returns any valid cached URL for the song regardless of quality.
  /// Used as a fast path — play instantly at whatever quality we have while
  /// the requested quality resolves.
  Future<Map<String, dynamic>?> getAnySongUrl(
    String objectHash,
    String objectType,
  ) async {
    await _ensureLoaded();

    final prefix = '${objectType}_${objectHash}_';
    for (final e in _memoryCache.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (e.value.isExpired) continue;
      try {
        final decoded = json.decode(e.value.data) as Map<String, dynamic>;
        if ((decoded['url']?.toString() ?? '').isNotEmpty) return decoded;
      } catch (_) {}
    }
    return null;
  }

  /// Cache a song URL with optional quality
  Future<void> cacheSongUrl(
    String objectHash,
    String objectType, {
    required String url,
    String? sourceType,
    String? quality,
    Map<String, dynamic>? extraData,
    Duration? expiry,
  }) async {
    await _ensureLoaded();

    final key = _makeKey(objectHash, objectType, quality: quality);
    final data = json.encode({
      'url': url,
      if (sourceType != null) 'sourceType': sourceType,
      if (extraData != null) ...extraData,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });

    _memoryCache[key] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(expiry ?? _expiryFor(url)),
    );

    await _persist();
  }

  /// YouTube/googlevideo URLs carry an `expire` epoch-seconds param — cache
  /// only until then (minus a small buffer). Everything else uses the default.
  static Duration _expiryFor(String url) {
    try {
      final uri = Uri.parse(url);
      final raw = uri.queryParameters['expire'];
      final epoch = raw == null ? null : int.tryParse(raw);
      if (epoch == null) return _defaultExpiry;
      final expires = DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
          .subtract(const Duration(minutes: 5));
      final left = expires.difference(DateTime.now());
      if (left.isNegative) return Duration.zero;
      return left < _defaultExpiry ? left : _defaultExpiry;
    } catch (_) {
      return _defaultExpiry;
    }
  }

  /// Clear specific song from cache
  Future<void> clearSong(String objectHash, String objectType) async {
    await _ensureLoaded();

    // Clear all qualities for this song
    _memoryCache.remove(_makeKey(objectHash, objectType));
    _memoryCache.removeWhere((key, _) => key.startsWith('${objectType}_$objectHash'));
    await _persist();
  }

  /// Clear entire cache
  Future<void> clearAll() async {
    _memoryCache = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Get cache stats
  Future<Map<String, int>> getStats() async {
    await _ensureLoaded();
    return {
      'total': _memoryCache.length,
      'valid': _memoryCache.values.where((e) => !e.isExpired).length,
      'expired': _memoryCache.values.where((e) => e.isExpired).length,
    };
  }
}
