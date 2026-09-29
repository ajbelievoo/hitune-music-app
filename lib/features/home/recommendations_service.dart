import '../../core/network/api_service.dart';
import '../../core/utils/cover_image_extractor.dart';
import '../player/models/track.dart';

/// Fetches personalized recommendations ("Made for you") from the backend.
///
/// Expected endpoint: `recommendations` (POST). Returns a list of items in
/// `data.recommendations` / `data.items`, each compatible with the standard
/// item shape used by home widgets. See docs/BACKEND_REQUIREMENTS.md.
class RecommendationsService {
  RecommendationsService._();
  static final RecommendationsService instance = RecommendationsService._();

  final ApiService _api = ApiService.instance;

  // These payloads are ~300KB each — cache them in memory so revisiting
  // home/browse screens doesn't re-download the same JSON every time.
  static const Duration _ttl = Duration(minutes: 20);
  final Map<String, ({DateTime at, List<Map<String, dynamic>> items})> _cache = {};

  List<Map<String, dynamic>>? _cached(String key) {
    final e = _cache[key];
    if (e == null || DateTime.now().difference(e.at) > _ttl) return null;
    return e.items;
  }

  /// Returns raw items or null when the backend has no recommendations.
  Future<List<Map<String, dynamic>>?> fetchRecommendations() async {
    final hit = _cached('recommendations');
    if (hit != null) return hit;

    final res = await _api.postPayloadRaw(endpoint: 'recommendations');
    if (!res.isSuccess || res.data == null) return null;

    final data = res.data!;
    final raw = data['recommendations'] ?? data['items'] ?? data['data'];
    if (raw is! List || raw.isEmpty) return null;

    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _cache['recommendations'] = (at: DateTime.now(), items: items);
    return items;
  }

  /// Returns raw items for a "Daily Mix"-style playlist strip.
  Future<List<Map<String, dynamic>>?> fetchDailyMixes() async {
    final hit = _cached('daily_mix');
    if (hit != null) return hit;

    final res = await _api.postPayloadRaw(endpoint: 'daily_mix');
    if (!res.isSuccess || res.data == null) return null;

    final data = res.data!;
    final raw = data['mixes'] ?? data['items'] ?? data['data'];
    if (raw is! List || raw.isEmpty) return null;

    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _cache['daily_mix'] = (at: DateTime.now(), items: items);
    return items;
  }

  /// Items for a "Because you listened to X" rail.
  Future<List<Map<String, dynamic>>?> fetchBecauseYouListened() async {
    final hit = _cached('recommendations_because');
    if (hit != null) return hit;

    final res = await _api.postPayloadRaw(endpoint: 'recommendations_because');
    if (!res.isSuccess || res.data == null) return null;
    final raw = res.data!['items'];
    if (raw is! List || raw.isEmpty) return null;
    final items = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    _cache['recommendations_because'] = (at: DateTime.now(), items: items);
    return items;
  }

  /// Convert a recommendation item into a [Track] when it is a track.
  static Track? itemToTrack(Map<String, dynamic> item) {
    final ot = (item['ot'] ?? item['object_type'] ?? item['o_type'] ?? item['type'])?.toString();
    final hash = (item['hash'] ?? item['object_hash'] ?? item['object'] ?? item['id'] ?? item['ID'])?.toString();
    final displayTitle = item['display'] is Map ? (item['display'] as Map)['title']?.toString() : null;
    final title = (item['title'] ?? displayTitle ?? item['name'])?.toString();
    if (hash == null || hash.isEmpty || title == null || title.isEmpty) return null;
    if (ot != null && ot.isNotEmpty && ot != 'm_track') return null;
    final artistLink = (item['sub_link'] ?? item['artist_link'])?.toString() ?? '';
    var artistSlug = (item['artist_slug'] ?? item['artistSlug'])?.toString() ?? '';
    if (artistSlug.isEmpty && artistLink.contains('artist/')) {
      final parts = artistLink.split('?').first.split('/').where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) artistSlug = parts.last;
    }
    return Track(
      id: hash,
      title: title,
      subtitle: (item['sub_title'] ?? item['sub_data'] ?? item['subtitle'] ?? item['artist'])?.toString(),
      url: (item['url'] ?? item['file'] ?? '').toString(),
      coverUrl: CoverImageExtractor.extract(item),
      artistSlug: artistSlug.isEmpty ? null : artistSlug,
      artistLink: artistLink.isEmpty ? null : artistLink,
      objectType: ot?.isNotEmpty == true ? ot : 'm_track',
      objectHash: hash,
    );
  }
}
