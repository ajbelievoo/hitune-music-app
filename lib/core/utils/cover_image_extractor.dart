import 'dart:convert';

import 'app_logger.dart';

/// Central helper to extract a usable image URL from the many backend
/// structures used across HiTune (HTML strings, maps, nested objects,
/// encoded HTML, srcset, etc.).
class CoverImageExtractor {
  CoverImageExtractor._();

  static const String _baseUrl = 'https://music.hitune.in';

  /// Try to pull out the best available image URL from [input].
  static String? extract(dynamic input, {String? fallbackBaseUrl}) {
    final base = fallbackBaseUrl ?? _baseUrl;
    final candidate = _extractCandidate(input);
    if (candidate == null || candidate.isEmpty) return null;

    final normalized = _upgradeToHighRes(_normalize(candidate, base));
    if (!_isValidImageUrl(normalized)) {
      AppLogger.d('[CoverImageExtractor] Rejected invalid URL: $normalized');
      return null;
    }
    return normalized;
  }

  static String? _extractCandidate(dynamic input) {
    if (input == null) return null;

    if (input is String) {
      final s = input.trim();
      if (s.isEmpty) return null;
      return _extractFromString(s);
    }

    if (input is Map) {
      return _extractFromMap(input);
    }

    if (input is List) {
      for (final v in input) {
        final got = _extractCandidate(v);
        if (got != null && got.isNotEmpty) return got;
      }
    }

    return _extractFromString(input.toString());
  }

  static String? _extractFromMap(Map<dynamic, dynamic> map) {
    // Priority keys in the order we want to try — full-size fields first,
    // thumbnail fields last so wallpaper surfaces stay sharp.
    final priority = [
      'cover_url',
      'cover_big',
      'image',
      'cover',
      'image_url',
      'img_url',
      'art',
      'photo',
      'background',
      'bg_img',
      'preview',
      'image_thumb',
      'thumb',
    ];

    for (final key in priority) {
      final value = map[key];
      if (value == null) continue;
      final got = _extractCandidate(value);
      if (got != null && got.isNotEmpty) return got;
    }

    // `url`/`link`-style keys usually point at the object's *page*, not an
    // image (e.g. "music/track/..."). Only accept them when they look like
    // an actual image resource.
    for (final key in ['url', 'link', 'web_address', 'play', 'src', 'href']) {
      final value = map[key];
      if (value == null) continue;
      final got = _extractCandidate(value);
      if (got != null && got.isNotEmpty && _looksLikeImage(got)) return got;
    }

    // Nested common objects.
    for (final nestedKey in ['display', 'raw', 'cover_data', 'image_data']) {
      final nested = map[nestedKey];
      if (nested is Map) {
        final got = _extractFromMap(nested);
        if (got != null && got.isNotEmpty) return got;
      }
    }

    // image_strings: { "1": { html: "<img src=...>" } }
    final strings = map['image_strings'];
    if (strings is Map) {
      for (final k in ['1', 1, 'full', 'large', 'medium', 'small', 'thumb']) {
        final entry = strings[k];
        if (entry == null) continue;
        final got = _extractCandidate(entry);
        if (got != null && got.isNotEmpty) return got;
      }
      // Try any key if specific ones failed.
      for (final v in strings.values) {
        final got = _extractCandidate(v);
        if (got != null && got.isNotEmpty) return got;
      }
    }

    // tds cells with class "cover"
    final tds = map['tds'];
    if (tds is List) {
      for (final cell in tds) {
        if (cell is! Map) continue;
        final cls = (cell['class'] ?? '').toString();
        if (!cls.split(' ').contains('cover')) continue;
        final val = (cell['val'] ?? '').toString();
        final got = _extractFromString(val);
        if (got != null && got.isNotEmpty) return got;
      }
    }

    // Generic: try every value as last resort.
    for (final v in map.values) {
      final got = _extractCandidate(v);
      if (got != null && got.isNotEmpty) return got;
    }

    return null;
  }

  static String? _extractFromString(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Backend uses literal booleans (e.g. background:false) — not images.
    if (s == 'true' || s == 'false' || s == 'null') return null;

    // URL-decode HTML-like strings.
    if (s.contains('%3C') || s.contains('%3E') || s.contains('%22') || s.contains('%27')) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }

    // Try parsing as JSON if it looks like an object/list.
    if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
      try {
        final decoded = jsonDecode(s);
        final got = _extractCandidate(decoded);
        if (got != null && got.isNotEmpty) return got;
      } catch (_) {}
    }

    if (s.contains('<')) {
      // srcset — scan every srcset attribute and within each pick the
      // entry with the largest descriptor ("url 300w" / "url 2x").
      // Entries without descriptors tie at 0, so the first <source> wins —
      // <picture> sources are ordered largest-media-first by the backend.
      final srcsetMatches = RegExp(r"""srcset=["\']([^"\']+)["\']""", caseSensitive: false).allMatches(s);
      for (final m in srcsetMatches) {
        final srcset = m.group(1);
        if (srcset == null || srcset.isEmpty) continue;
        String? best;
        var bestScore = -1.0;
        for (final part in srcset.split(',')) {
          final seg = part.trim();
          if (seg.isEmpty) continue;
          final sp = seg.indexOf(' ');
          final url = sp > 0 ? seg.substring(0, sp) : seg;
          var score = 0.0;
          if (sp > 0) {
            final descriptor = seg.substring(sp + 1).trim();
            score = double.tryParse(descriptor.replaceAll(RegExp(r'[wx]$', caseSensitive: false), '')) ?? 0;
          }
          if (url.isNotEmpty && score > bestScore) {
            bestScore = score;
            best = url;
          }
        }
        if (best != null && best.isNotEmpty) return best;
      }

      // <img src="..." or <img src='...'>
      final imgMatch = RegExp(r"""<img[^>]+src=["\']([^"\'>\s]+)["\']""", caseSensitive: false).firstMatch(s);
      if (imgMatch != null) {
        final url = imgMatch.group(1);
        if (url != null && url.isNotEmpty) return url;
      }

      // CSS background-image: url(...)
      final bgMatch = RegExp(r"""url\(["\']?([^"\')>\s]+)["\']?\)""", caseSensitive: false).firstMatch(s);
      if (bgMatch != null) {
        final url = bgMatch.group(1);
        if (url != null && url.isNotEmpty) return url;
      }

      // data-src (lazy loaded images)
      final dataSrcMatch = RegExp(r"""data-src=["\']([^"\'>\s]+)["\']""", caseSensitive: false).firstMatch(s);
      if (dataSrcMatch != null) {
        final url = dataSrcMatch.group(1);
        if (url != null && url.isNotEmpty) return url;
      }
    }

    // Not HTML - direct URL/path.
    if (!s.contains('<')) {
      if (s.isNotEmpty) return s;
    }

    // Fallback: any http(s) URL embedded in the string.
    final fallback = RegExp(r"""https?://[^\s\'"<>]+""", caseSensitive: false).firstMatch(s);
    if (fallback != null) {
      final url = fallback.group(0);
      if (url != null && url.isNotEmpty) return url;
    }

    return null;
  }

  static String _normalize(String url, String base) {
    var u = url.trim().replaceAll(r'\/', '/');

    // Convert WebP to JPEG for broader Android compatibility.
    final webpRegex = RegExp(r'\.webp([?#]|$)', caseSensitive: false);
    if (webpRegex.hasMatch(u)) {
      u = u.replaceAll(webpRegex, '.jpg\$1');
    }

    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return '$base$u';
    return '$base/$u';
  }

  /// Upgrades known CDN thumbnail URLs to their high-resolution variants.
  /// The image hash stays the same — only the embedded size token changes.
  static String _upgradeToHighRes(String url) {
    var u = url;

    // i.scdn.co (Spotify CDN) size tokens:
    //   ab67616d00004851 = 64px  | ab67616d00001e02 = 300px  -> ab67616d0000b273 = 640px (album)
    //   ab6761610000f8d0 = 160px -> ab6761610000e5eb = 640px (artist)
    if (u.contains('i.scdn.co/')) {
      u = u
          .replaceAll('ab67616d00004851', 'ab67616d0000b273')
          .replaceAll('ab67616d00001e02', 'ab67616d0000b273')
          .replaceAll('ab6761610000f8d0', 'ab6761610000e5eb');
    }

    // Apple artwork (mzstatic / itunes): "{w}x{h}bb.jpg" URLs are resizable.
    try {
      final host = Uri.parse(u).host;
      if (host.contains('mzstatic') || host.contains('itunes')) {
        u = u.replaceAllMapped(
          RegExp(r'\d{2,4}x\d{2,4}bb\.', caseSensitive: false),
          (_) => '600x600bb.',
        );
      }
    } catch (_) {}

    return u;
  }

  /// Heuristic: does this URL look like an image (vs. an HTML page route)?
  static bool _looksLikeImage(String url) {
    final s = url.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (RegExp(r'\.(jpe?g|png|webp|gif|bmp|avif)([?#].*)?$').hasMatch(s)) return true;
    try {
      final uri = Uri.parse(s);
      final host = uri.host;
      if (host.contains('scdn') ||
          host.contains('itunes') ||
          host.contains('mzstatic') ||
          host.contains('cloudfront') ||
          host.contains('imgur') ||
          host.contains('imgix') ||
          host.contains('akamai') ||
          host.contains('googleusercontent') ||
          host.contains('spotify')) {
        return true;
      }
      final path = uri.path;
      return path.contains('/image') ||
          path.contains('/img/') ||
          path.contains('/cover') ||
          path.contains('/thumb') ||
          path.contains('/uploads/') ||
          path.contains('/files/') ||
          path.contains('/media/');
    } catch (_) {
      return false;
    }
  }

  /// True when [url] is a real, loadable image URL — rejects backend dummy
  /// placeholders, page routes and malformed URLs. Screens that extract
  /// cover candidates by hand can validate them through this.
  static bool isUsableUrl(String? url) => url != null && _isValidImageUrl(url);

  static bool _isValidImageUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;
    if (u.contains(' ')) return false;
    if (u.startsWith('data:')) return false;
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    try {
      final uri = Uri.parse(u);
      final host = uri.host.trim().toLowerCase();
      if (host.isEmpty || !host.contains('.')) return false;
      if (host.endsWith('.')) return false;
      final parts = host.split('.').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) return false;
      final tld = parts.last;
      if (tld.length < 2) return false;
      final segs = uri.pathSegments;
      // Backend's own dummy placeholders (e.g. .../placeholder/.../dummy_*_dm2.png)
      // carry no artwork — treat as "no cover" so widgets show the styled
      // fallback instead of an ugly grey "DM2" box.
      if (segs.contains('placeholder')) return false;
      if (segs.isNotEmpty && segs.last.toLowerCase().startsWith('dummy_')) return false;
      // Backend page routes like /music/track/... are not images.
      if (segs.length > 1 &&
          segs.first == 'music' &&
          const {'track', 'artist', 'album', 'playlist', 'radio', 'genre', 'video', 'user', 'page'}
              .contains(segs[1])) {
        if (!RegExp(r'\.(jpe?g|png|webp|gif|bmp|avif)$', caseSensitive: false).hasMatch(uri.path)) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
