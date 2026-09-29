import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// Looks up public album/track artwork on the iTunes Search API when the
/// backend has no cover image for an item (it returns a `dummy_*` placeholder
/// for those). Results — including misses — are cached in memory so a
/// rebuild or a second card for the same title never refetches.
class ArtworkLookup {
  ArtworkLookup._();
  static final ArtworkLookup instance = ArtworkLookup._();

  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inflight = {};

  /// Returns a ~600px artwork URL for [title] (+ optional artist [subtitle]),
  /// or null when nothing matches.
  Future<String?> lookup(String title, [String? subtitle]) {
    final term = _buildTerm(title, subtitle);
    if (term.isEmpty) return Future<String?>.value();
    if (_cache.containsKey(term)) return Future<String?>.value(_cache[term]);
    return _inflight.putIfAbsent(term, () => _fetch(term));
  }

  Future<String?> _fetch(String term) async {
    String? result;
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'media': 'music',
        'limit': '6',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final results = body is Map ? body['results'] : null;
        if (results is List) {
          for (final r in results) {
            if (r is! Map) continue;
            final art = r['artworkUrl100']?.toString();
            if (art != null && art.isNotEmpty) {
              // iTunes artwork URLs are resizable — ask for the big one.
              result = art.replaceAllMapped(
                RegExp(r'\d{2,4}x\d{2,4}bb\.'),
                (_) => '600x600bb.',
              );
              break;
            }
          }
        }
      }
    } catch (e) {
      AppLogger.d('[ArtworkLookup] lookup failed for "$term": $e');
    }
    _cache[term] = result;
    _inflight.remove(term);
    return result;
  }

  /// Builds a search term: strips "(From "...")", "- Single"-style suffixes
  /// and appends the first artist name for a tighter match.
  static String _buildTerm(String title, String? subtitle) {
    var t = title
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[-–—]\s*(single|ep|album)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) t = title.trim();
    final artist = (subtitle ?? '').split(RegExp(r'[,&]')).first.trim();
    return artist.isEmpty ? t : '$t $artist';
  }
}
