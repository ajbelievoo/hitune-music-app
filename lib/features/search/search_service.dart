import '../../core/network/api_service.dart';

/// Lightweight suggestion returned by the search backend.
class SearchSuggestion {
  final String text;

  const SearchSuggestion(this.text);

  @override
  String toString() => text;
}

/// Service for search suggestions and related search helpers.
///
/// The backend search endpoint is reused to derive top suggestions. Replace
/// `getSuggestions` with a dedicated backend endpoint (`search_suggest` etc.)
/// once one is available.
class SearchService {
  SearchService._();

  static final SearchService instance = SearchService._();

  final ApiService _api = ApiService.instance;

  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final res = await _api.postPayloadRaw(
      endpoint: 'search',
      data: {
        'query': q,
        'page': '2',
        'ot': 'm_track',
      },
    );

    if (!res.isSuccess || res.data == null) {
      return const [];
    }

    final payload = res.data!;
    final suggestions = <String>{};

    // Try the common "widgets" layout.
    final widgets = payload['widgets'];
    if (widgets is List) {
      for (final w in widgets) {
        if (w is! Map) continue;
        final items = w['items'];
        if (items is List) {
          for (final item in items) {
            if (item is! Map) continue;
            final text = _extractTitle(item);
            if (text != null && text.isNotEmpty) {
              suggestions.add(text);
            }
          }
        }
      }
    } else if (widgets is Map) {
      for (final value in widgets.values) {
        if (value is List) {
          for (final item in value) {
            if (item is! Map) continue;
            final text = _extractTitle(item);
            if (text != null && text.isNotEmpty) {
              suggestions.add(text);
            }
          }
        } else if (value is Map) {
          final items = value['items'];
          if (items is List) {
            for (final item in items) {
              if (item is! Map) continue;
              final text = _extractTitle(item);
              if (text != null && text.isNotEmpty) {
                suggestions.add(text);
              }
            }
          }
        }
      }
    }

    // Try a flat "items" list as a fallback.
    final directItems = payload['items'];
    if (directItems is List) {
      for (final item in directItems) {
        if (item is! Map) continue;
        final text = _extractTitle(item);
        if (text != null && text.isNotEmpty) {
          suggestions.add(text);
        }
      }
    }

    return suggestions.take(5).map((s) => SearchSuggestion(s)).toList();
  }

  String? _extractTitle(Map<dynamic, dynamic> item) {
    final title = item['title'];
    if (title is String && title.isNotEmpty) {
      return _cleanHtml(title);
    }

    final raw = item['raw'];
    if (raw is Map) {
      final rawTitle = raw['title'];
      if (rawTitle is String && rawTitle.isNotEmpty) {
        return _cleanHtml(rawTitle);
      }
    }

    final tds = item['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        if (!cls.split(' ').contains('title')) continue;
        final val = (cell['val'] ?? '').toString();
        if (val.isNotEmpty) return _cleanHtml(val);
      }
    }

    return null;
  }

  String _cleanHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
