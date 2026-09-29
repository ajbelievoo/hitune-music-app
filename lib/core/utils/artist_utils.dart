import '../../features/player/models/track.dart';

/// Artist-slug resolution shared by player / mini-player / search / sheets.
///
/// Order: explicit artistSlug → parse `artist/<slug>` out of artistLink →
/// slugify the artist name (backend slugs are lowercase+underscore, e.g.
/// "ROHITAK ROCK" -> `rohitak_rock`).
class ArtistUtils {
  ArtistUtils._();

  static String slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '')
        .trim();
  }

  static String? slugFromLink(String link) {
    final cleaned = link.startsWith('/') ? link.substring(1) : link;
    final m = RegExp(r'artist/([^/?#]+)', caseSensitive: false).firstMatch(cleaned);
    final slug = m?.group(1);
    return (slug == null || slug.isEmpty) ? null : slug;
  }

  static String? slugFromTrack(Track t) {
    // Radio streams have no artist page — subtitle is "Live Radio", which
    // would slugify to a bogus `live_radio` artist slug (404 -> Invalid JSON).
    if (t.id.startsWith('radio:') || t.objectType == 'radio') return null;

    final direct = (t.artistSlug ?? '').trim();
    if (direct.isNotEmpty) return direct;

    final link = (t.artistLink ?? '').trim();
    if (link.isNotEmpty) {
      final slug = slugFromLink(link);
      if (slug != null) return slug;
    }

    // Last resort: slugify the artist display name. Subtitles sometimes
    // carry several artists ("A, B" / "A & B") — take the first one.
    final sub = (t.subtitle ?? '').trim();
    if (sub.isEmpty) return null;
    final first = sub.split(RegExp(r'[,&]')).first.trim();
    final slug = slugify(first);
    return slug.isEmpty ? null : slug;
  }
}
