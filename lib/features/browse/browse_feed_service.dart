import '../../core/network/api_service.dart';
import '../home/recommendations_service.dart';

/// Feeds the Browse tab from endpoints that actually exist on the backend.
///
/// There are no dedicated `/albums`, `/artists`, `/tracks`, `/genre/*`
/// endpoints — they return 403. Instead the app reuses:
/// - `bofClient/single/page/?slug=home` widgets (items arrive either as a
///   List or as a `Map<pageNumber, List>`)
/// - `search` for genre queries (its `widgets` payload is a map of
///   object-type groups, each holding paged `items`)
/// - `radios` for radio stations
/// - `recommendations` / `daily_mix` to top up track lists
class BrowseFeedService {
  BrowseFeedService._();
  static final BrowseFeedService instance = BrowseFeedService._();

  final ApiService _api = ApiService.instance;

  /// `items` arrives either as a List or as `{page: [...]}` — normalize.
  static List<Map<String, dynamic>> normalizeItems(Object? raw) {
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    } else if (raw is Map) {
      for (final v in raw.values) {
        if (v is List) {
          for (final e in v) {
            if (e is Map) out.add(Map<String, dynamic>.from(e));
          }
        }
      }
    }
    return out;
  }

  static String? _ot(Map<String, dynamic> item) =>
      (item['ot'] ?? item['object_type'] ?? item['o_type'] ?? item['type'])?.toString();

  static String _dedupeKey(Map<String, dynamic> item) =>
      (item['hash'] ?? item['object_hash'] ?? item['id'] ?? item['ID'] ?? item['title'])?.toString() ?? '';

  // The home payload is re-fetched by every browse tab — cache it briefly
  // so opening Albums/Artists/Tracks back-to-back doesn't repeat the call.
  static const Duration _homeTtl = Duration(minutes: 10);
  Map<String, dynamic>? _homeCache;
  DateTime? _homeCacheAt;

  Future<Map<String, dynamic>?> _homePayload() async {
    final hit = _homeCache;
    if (hit != null &&
        _homeCacheAt != null &&
        DateTime.now().difference(_homeCacheAt!) < _homeTtl) {
      return hit;
    }
    final res = await _api.postPayloadRaw(endpoint: 'bofClient/single/page/?slug=home');
    if (!res.isSuccess || res.data == null) return null;
    _homeCache = res.data;
    _homeCacheAt = DateTime.now();
    return res.data;
  }

  /// Collect items of [objectType] (e.g. `m_track`, `m_album`, `m_artist`)
  /// from the home page widgets.
  Future<List<Map<String, dynamic>>> homeItems(String objectType) async {
    final data = await _homePayload();
    if (data == null) return const [];

    final widgets = data['widgets'];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    // `widgets` may be a List or a keyed Map depending on the page.
    final Iterable<dynamic> widgetList =
        widgets is List ? widgets : (widgets is Map ? widgets.values : const []);
    if (widgetList.isEmpty) return out;

    for (final w in widgetList) {
      if (w is! Map) continue;
      final widgetMap = Map<String, dynamic>.from(w);
      final display = widgetMap['display'] is Map ? Map<String, dynamic>.from(widgetMap['display'] as Map) : null;
      final widgetOt = (display?['o_type'] ?? '').toString();

      for (final item in normalizeItems(widgetMap['items'] ?? display?['widgets'])) {
        final ot = _ot(item) ?? widgetOt;
        if (objectType.isNotEmpty && ot != objectType) continue;
        final key = _dedupeKey(item);
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(item);
      }
    }
    return out;
  }

  /// Extra tracks from the recommendations endpoints (items are m_track).
  /// Goes through [RecommendationsService]'s cache — those payloads are
  /// ~300KB each and don't change minute-to-minute.
  Future<List<Map<String, dynamic>>> recommendedTracks() async {
    final recos = RecommendationsService.instance;
    final out = <Map<String, dynamic>>[];
    for (final fetch in [recos.fetchRecommendations, recos.fetchDailyMixes]) {
      try {
        final items = await fetch();
        if (items != null) out.addAll(items);
      } catch (_) {
        // best-effort top-up; ignore failures
      }
    }
    return out;
  }

  /// Genre browsing via the `search` endpoint. `widgets` is a map of
  /// object-type groups; each group carries paged `items`.
  Future<List<Map<String, dynamic>>> searchGenre(List<String> queries) async {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final query in queries) {
      final res = await _api.postPayloadRaw(
        endpoint: 'search',
        data: {'query': query, 'page': '2', 'ot': 'm_track'},
      );
      if (!res.isSuccess || res.data == null) continue;

      final widgets = res.data!['widgets'];
      if (widgets is! Map) continue;

      for (final entry in widgets.entries) {
        final group = entry.value;
        if (group is! Map) continue;
        final groupOt = (group['display'] is Map
                ? (group['display'] as Map)['o_type']
                : (group['o_type'] ?? group['object_type']))
            ?.toString();
        // Only track groups (and the mixed "best" group) belong here.
        if (groupOt != null && groupOt.isNotEmpty && groupOt != 'm_track') continue;

        for (final item in normalizeItems(group['items'])) {
          final ot = _ot(item);
          if (ot != null && ot.isNotEmpty && ot != 'm_track') continue;
          final key = _dedupeKey(item);
          if (key.isEmpty || !seen.add(key)) continue;
          out.add(item);
        }
      }
    }
    return out;
  }

  /// The catalog has no `m_artist` objects in the feed — derive artist rows
  /// from each track's `sub_data` (artist name) + `sub_link` (artist slug).
  Future<List<Map<String, dynamic>>> derivedArtists() async {
    final tracks = <Map<String, dynamic>>[
      ...await homeItems('m_track'),
      ...await recommendedTracks(),
    ];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final t in tracks) {
      final link = (t['sub_link'] ?? '').toString();
      if (!link.contains('artist')) continue;
      final slug = link.split('/').last;
      if (slug.isEmpty || !seen.add(slug)) continue;
      out.add({
        'name': (t['sub_data'] ?? '').toString(),
        'title': (t['sub_data'] ?? '').toString(),
        'url': link,
        'cover_url': t['cover_url'] ?? t['cover'],
        'ot': 'm_artist',
      });
    }
    return out;
  }

  /// Radio stations from the `radios` endpoint (`items` list).
  Future<List<Map<String, dynamic>>> radios() async {
    final res = await _api.postPayloadRaw(endpoint: 'radios');
    if (!res.isSuccess || res.data == null) return const [];
    return normalizeItems(res.data!['items'] ?? res.data!['radios'] ?? res.data!['data']);
  }
}
